//
//  WarpEngine.swift
//  Warp
//

import AppKit
import Combine
@_weakLinked import DroppyKit
import Foundation
import Network
import OSLog


// MARK: - Safe Subprocess Helpers

private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private let maxBytes: Int

    init(maxBytes: Int = 100_000) {
        self.maxBytes = maxBytes
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        if buffer.count + chunk.count > maxBytes {
            let overflow = (buffer.count + chunk.count) - maxBytes
            if overflow < buffer.count {
                buffer.removeFirst(overflow)
            } else {
                buffer.removeAll()
            }
        }
        buffer.append(chunk)
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll()
    }
}

private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if didResume { return false }
        didResume = true
        return true
    }
}

private final class Watchdog: @unchecked Sendable {
    let workItem: DispatchWorkItem
    init(_ workItem: DispatchWorkItem) { self.workItem = workItem }
    func cancel() { workItem.cancel() }
}

private final class ProcessControl: @unchecked Sendable {
    enum StopReason: Equatable { case cancelled, timedOut }

    private let lock = NSLock()
    private let process: Process
    private var reason: StopReason?

    init(process: Process) { self.process = process }

    var stopReason: StopReason? {
        lock.lock()
        defer { lock.unlock() }
        return reason
    }

    func run() throws {
        lock.lock()
        defer { lock.unlock() }
        guard reason == nil else { throw CancellationError() }
        try process.run()
    }

    func stop(timedOut: Bool = false) {
        lock.lock()
        let running = process.isRunning
        if timedOut && !running {
            lock.unlock()
            return
        }
        if reason == nil { reason = timedOut ? .timedOut : .cancelled }
        if running {
            let pid = process.processIdentifier
            if pid > 0 {
                kill(pid, SIGTERM)
            }
            process.terminate()
        }
        lock.unlock()
        guard running else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [process] in
            if process.isRunning {
                let pid = process.processIdentifier
                if pid > 0 {
                    kill(pid, SIGKILL)
                }
                process.terminate()
            }
        }
    }
}

@MainActor
public final class WarpEngine: ObservableObject {
    public struct LatestStats: Equatable, Sendable {
        public let downloadMbps: Double
        public let uploadMbps: Double
        public let pingMs: Double
        public let timestamp: Date
    }

    @Published public private(set) var phase: SpeedtestPhase = .idle
    @Published public private(set) var currentTelemetry: SpeedtestTelemetry?
    @Published public private(set) var currentGaugeSpeed: Double = 0.0
    @Published public private(set) var displayedGaugeSpeed: Double = 0.0
    @Published public private(set) var testProgress: Double = 0.0
    @Published public private(set) var estimatedRemainingSeconds: Int = 0
    @Published public private(set) var history: [WarpHistoryItem] = []
    @Published public var speedUnit: SpeedUnit = .mbps {
        didSet { savePreferences() }
    }
    @Published public var customCLIPath: String = "" {
        didSet {
            savePreferences()
            detectCLI()
        }
    }
    @Published public var showHUDOnFinish: Bool = true {
        didSet { savePreferences() }
    }
    @Published public var testDuration: TestDuration = .sec30 {
        didSet {
            savePreferences()
            if !phase.isTesting {
                estimatedRemainingSeconds = testDuration.rawValue
            }
        }
    }
    private var isLoadingPreferences = false

    @Published public var retainLastResult: Bool = true {
        didSet {
            guard !isLoadingPreferences else { return }
            handleRetainSettingChange()
            savePreferences()
        }
    }

    public enum NetworkInterfaceKind: String, Sendable {
        case wifi = "Wi-Fi"
        case ethernet = "Ethernet"
        case cellular = "Cellular"
        case other = "Other"

        public var systemImage: String {
            switch self {
            case .wifi: return "wifi"
            case .ethernet: return "cable.connector"
            case .cellular: return "antenna.radiowaves.left.and.right"
            case .other: return "network"
            }
        }
    }

    @Published public private(set) var primaryInterfaceType: NetworkInterfaceKind = .wifi
    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "com.warp.pathMonitor", qos: .utility)

    public static let defaultNativeExecutable = "/usr/bin/networkQuality"
    @Published public private(set) var detectedCLIPath: String?

    public var isNativeEngine: Bool {
        detectedCLIPath == Self.defaultNativeExecutable
    }

    public var activeInterfaceIcon: String {
        if let telemetry = currentTelemetry ?? lastTelemetry, !telemetry.interfaceType.isEmpty {
            let lower = telemetry.interfaceType.lowercased()
            if lower.contains("ethernet") || lower.contains("wired") {
                return "cable.connector"
            } else if lower.contains("cellular") {
                return "antenna.radiowaves.left.and.right"
            } else {
                return "wifi"
            }
        }
        return primaryInterfaceType.systemImage
    }

    public var latestRecordedStats: LatestStats? {
        if let telemetry = currentTelemetry,
           telemetry.downloadMbps > 0 || telemetry.uploadMbps > 0 || telemetry.pingMs > 0 {
            return LatestStats(
                downloadMbps: telemetry.downloadMbps,
                uploadMbps: telemetry.uploadMbps,
                pingMs: telemetry.pingMs,
                timestamp: telemetry.timestamp
            )
        }
        if phase.isTesting || retainLastResult {
            if let last = resolvedLastTelemetry,
               last.downloadMbps > 0 || last.uploadMbps > 0 || last.pingMs > 0 {
                return LatestStats(
                    downloadMbps: last.downloadMbps,
                    uploadMbps: last.uploadMbps,
                    pingMs: last.pingMs,
                    timestamp: last.timestamp
                )
            }
        }
        return nil
    }

    public var formattedLatestStatsForClipboard: String? {
        guard let stats = latestRecordedStats else { return nil }
        let dl = stats.downloadMbps > 0 ? speedUnit.format(mbps: stats.downloadMbps) : "--"
        let ul = stats.uploadMbps > 0 ? speedUnit.format(mbps: stats.uploadMbps) : "--"
        let ping = stats.pingMs > 0 ? String(format: "%.0f ms", stats.pingMs) : "--"
        return "Download: \(dl) · Upload: \(ul) · Ping: \(ping)"
    }

    private var activeTestTask: Task<Void, Never>?
    private var gaugeSimulationTimer: Timer?
    private var currentControl: ProcessControl?
    private var lastTelemetry: SpeedtestTelemetry?
    private weak var preferences: (any DropletPreferencesService)?
    private var downloadPhaseStart: Date?
    private var uploadPhaseStart: Date?
    private var estimatedDownloadDuration: TimeInterval = 14.0
    private var estimatedUploadDuration: TimeInterval = 24.0
    private var hasMeasuredDownload = false
    private var hasMeasuredUpload = false
    private var lastDisplayNumberUpdate: Date = .distantPast
    private static let displayNumberUpdateInterval: TimeInterval = 0.38

    public init() {
        detectCLI()
        startPathMonitor()
    }

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if path.usesInterfaceType(.wiredEthernet) {
                    self.primaryInterfaceType = .ethernet
                } else if path.usesInterfaceType(.cellular) {
                    self.primaryInterfaceType = .cellular
                } else if path.usesInterfaceType(.wifi) {
                    self.primaryInterfaceType = .wifi
                } else {
                    self.primaryInterfaceType = .other
                }
            }
        }
        monitor.start(queue: monitorQueue)
        self.pathMonitor = monitor
    }

    // MARK: - Lifecycle

    public func attach(preferences: any DropletPreferencesService) {
        self.preferences = preferences
        loadPreferences()
        detectCLI()
    }

    public func detachPreferences() {
        preferences = nil
    }

    public func stop() {
        cancelTest()
        stopGaugeSimulation()
    }

    deinit {
        pathMonitor?.cancel()
        pathMonitor = nil
        gaugeSimulationTimer?.invalidate()
        autoResetTask?.cancel()
        activeTestTask?.cancel()
        currentControl?.stop()
    }

    // MARK: - Native CLI Detection

    public func detectCLI() {
        if !customCLIPath.isEmpty && FileManager.default.isExecutableFile(atPath: customCLIPath) {
            detectedCLIPath = customCLIPath
            return
        }

        let candidates = [
            Self.defaultNativeExecutable,
            "/usr/local/bin/networkQuality"
        ]

        detectedCLIPath = candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public var isCLIInstalled: Bool {
        detectedCLIPath != nil
    }

    // MARK: - Speed Test Execution

    public func startTest() {
        guard !phase.isTesting else { return }
        detectCLI()

        guard let cliPath = detectedCLIPath else {
            phase = .failed("macOS networkQuality binary not found at \(Self.defaultNativeExecutable).")
            return
        }

        autoResetTask?.cancel()
        autoResetTask = nil
        activeTestTask?.cancel()
        currentTelemetry = nil
        phase = .locating
        currentGaugeSpeed = 0.0
        displayedGaugeSpeed = 0.0
        let maxPhaseSeconds = testDuration.perPhaseSeconds
        let phaseTimeout = Double(maxPhaseSeconds + 10)

        estimatedRemainingSeconds = max(1, testDuration.rawValue)
        downloadPhaseStart = nil
        uploadPhaseStart = nil
        lastDisplayNumberUpdate = .distantPast

        activeTestTask = Task { [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()

                self.phase = .locating
                self.startGaugeSimulation()

                self.downloadPhaseStart = Date()
                self.phase = .downloading(currentMbps: 1.0)
                let (dlStdout, _) = try await self.executeProcess(
                    executable: cliPath,
                    arguments: ["-c", "-v", "-u", "-M", "\(maxPhaseSeconds)"],
                    timeoutSeconds: phaseTimeout
                )

                try Task.checkCancellation()

                if let dlStart = self.downloadPhaseStart {
                    let measured = max(4.0, Date().timeIntervalSince(dlStart))
                    self.estimatedDownloadDuration = measured
                    self.hasMeasuredDownload = true
                }

                guard let dlJsonData = dlStdout.data(using: .utf8) else {
                    throw NSError(domain: "WarpEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to read download test output."])
                }

                let decoder = JSONDecoder()
                let dlOutput = try decoder.decode(NetworkQualityOutput.self, from: dlJsonData)
                let dlTelemetry = dlOutput.toTelemetry()

                self.currentTelemetry = dlTelemetry
                self.currentGaugeSpeed = dlTelemetry.downloadMbps
                self.displayedGaugeSpeed = dlTelemetry.downloadMbps
                self.lastDisplayNumberUpdate = Date()
                self.testProgress = 0.50
                self.estimatedRemainingSeconds = max(1, Int(self.testDuration.rawValue - self.testDuration.perPhaseSeconds))
                WarpLog.info("Download completed: \(dlTelemetry.downloadMbps) Mbps, Ping \(dlTelemetry.pingMs) ms")

                self.uploadPhaseStart = Date()
                self.phase = .uploading(currentMbps: 1.0)

                let (ulStdout, _) = try await self.executeProcess(
                    executable: cliPath,
                    arguments: ["-c", "-v", "-d", "-M", "\(maxPhaseSeconds)"],
                    timeoutSeconds: phaseTimeout
                )

                try Task.checkCancellation()

                if let ulStart = self.uploadPhaseStart {
                    let measured = max(4.0, Date().timeIntervalSince(ulStart))
                    self.estimatedUploadDuration = measured
                    self.hasMeasuredUpload = true
                }

                guard let ulJsonData = ulStdout.data(using: .utf8) else {
                    throw NSError(domain: "WarpEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to read upload test output."])
                }

                let ulOutput = try decoder.decode(NetworkQualityOutput.self, from: ulJsonData)
                let ulTelemetry = ulOutput.toTelemetry()
                let finalRPM = ulOutput.responsiveness ?? ulOutput.ulResponsiveness ?? dlTelemetry.responsivenessRPM

                let finalTelemetry = SpeedtestTelemetry(
                    downloadMbps: dlTelemetry.downloadMbps,
                    uploadMbps: ulTelemetry.uploadMbps,
                    pingMs: dlTelemetry.pingMs,
                    jitterMs: 0.0,
                    responsivenessRPM: finalRPM,
                    serverName: dlTelemetry.serverName,
                    serverSponsor: "Apple Edge CDN",
                    serverCountry: "macOS Native",
                    serverDistanceKm: 0.0,
                    serverHost: dlTelemetry.serverHost,
                    clientIP: dlTelemetry.clientIP,
                    clientISP: dlTelemetry.clientISP,
                    clientCountry: "",
                    bytesReceived: dlTelemetry.bytesReceived,
                    bytesSent: ulOutput.ulBytesTransferred ?? 0,
                    timestamp: Date(),
                    shareURL: nil,
                    interfaceType: dlTelemetry.interfaceType,
                    protocolName: dlTelemetry.protocolName,
                    workingLatencyMs: max(dlTelemetry.workingLatencyMs, ulTelemetry.workingLatencyMs),
                    tcpHandshakeMs: dlTelemetry.tcpHandshakeMs > 0 ? dlTelemetry.tcpHandshakeMs : ulTelemetry.tcpHandshakeMs,
                    tlsHandshakeMs: dlTelemetry.tlsHandshakeMs > 0 ? dlTelemetry.tlsHandshakeMs : ulTelemetry.tlsHandshakeMs
                )

                self.stopGaugeSimulation()
                self.lastTelemetry = finalTelemetry
                self.currentTelemetry = finalTelemetry
                self.currentGaugeSpeed = finalTelemetry.downloadMbps
                self.displayedGaugeSpeed = finalTelemetry.downloadMbps
                self.testProgress = 1.0
                self.estimatedRemainingSeconds = 0
                self.phase = .completed

                WarpLog.info("Network test completed: DL \(finalTelemetry.downloadMbps) Mbps, UL \(finalTelemetry.uploadMbps) Mbps, Ping \(finalTelemetry.pingMs) ms, RPM \(finalTelemetry.responsivenessRPM)")
                self.addHistory(item: WarpHistoryItem(telemetry: finalTelemetry))
                self.handleVisibilityChange()
            } catch is CancellationError {
                self.stopGaugeSimulation()
                self.phase = .idle
                self.currentGaugeSpeed = 0.0
                self.displayedGaugeSpeed = 0.0
                self.testProgress = 0.0
                self.estimatedRemainingSeconds = 0
                WarpLog.info("Speedtest cancelled")
            } catch {
                self.stopGaugeSimulation()
                let errMessage = error.localizedDescription
                WarpLog.error("Speedtest failed: \(errMessage)")
                self.phase = .failed(errMessage)
                self.currentGaugeSpeed = 0.0
                self.displayedGaugeSpeed = 0.0
                self.testProgress = 0.0
                self.estimatedRemainingSeconds = 0
            }
            self.activeTestTask = nil
        }
    }

    private var isShelfVisible = false
    private var isExpandedVisible = false
    private var autoResetTask: Task<Void, Never>?

    public func shelfVisibilityDidChange(isVisible: Bool) {
        isShelfVisible = isVisible
        handleVisibilityChange()
    }

    public func expandedVisibilityDidChange(isVisible: Bool) {
        isExpandedVisible = isVisible
        handleVisibilityChange()
    }

    private func handleVisibilityChange() {
        if isShelfVisible || isExpandedVisible {
            autoResetTask?.cancel()
            autoResetTask = nil
        } else if phase == .completed {
            scheduleAutoReset()
        }
    }

    private func scheduleAutoReset() {
        guard !retainLastResult else { return }
        guard !isShelfVisible && !isExpandedVisible else { return }
        autoResetTask?.cancel()
        autoResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 14_000_000_000)
            guard !Task.isCancelled, let self, self.phase == .completed else { return }
            guard !self.retainLastResult else { return }
            guard !self.isShelfVisible && !self.isExpandedVisible else { return }
            self.phase = .idle
            self.currentTelemetry = nil
            self.currentGaugeSpeed = 0.0
            self.displayedGaugeSpeed = 0.0
            self.testProgress = 0.0
            self.estimatedRemainingSeconds = 0
            WarpLog.info("Shelf result auto-dismissed back to idle while out of view")
        }
    }

    private func handleRetainSettingChange() {
        autoResetTask?.cancel()
        autoResetTask = nil
        if !retainLastResult {
            if phase == .completed {
                phase = .idle
                currentTelemetry = nil
                currentGaugeSpeed = 0.0
                displayedGaugeSpeed = 0.0
                testProgress = 0.0
                estimatedRemainingSeconds = 0
            }
        } else {
            if currentTelemetry == nil, let last = resolvedLastTelemetry {
                currentTelemetry = last
                phase = .completed
                currentGaugeSpeed = last.downloadMbps
                displayedGaugeSpeed = last.downloadMbps
                testProgress = 1.0
                estimatedRemainingSeconds = 0
            }
        }
    }

    private var resolvedLastTelemetry: SpeedtestTelemetry? {
        if let lastTelemetry { return lastTelemetry }
        guard let first = history.first else { return nil }
        return SpeedtestTelemetry(
            downloadMbps: first.downloadMbps,
            uploadMbps: first.uploadMbps,
            pingMs: first.pingMs,
            serverName: first.serverName,
            serverSponsor: "Apple Edge CDN",
            serverCountry: "macOS Native",
            serverDistanceKm: 0,
            serverHost: first.serverName,
            clientIP: "",
            clientISP: first.clientISP,
            clientCountry: "",
            bytesReceived: 0,
            bytesSent: 0,
            timestamp: first.timestamp
        )
    }

    public func cancelTest() {
        autoResetTask?.cancel()
        autoResetTask = nil
        activeTestTask?.cancel()
        activeTestTask = nil
        currentControl?.stop()
        currentControl = nil
        stopGaugeSimulation()
        phase = .idle
        currentGaugeSpeed = 0.0
        displayedGaugeSpeed = 0.0
        testProgress = 0.0
        estimatedRemainingSeconds = 0
        WarpLog.info("Test stopped by user")
    }

    // MARK: - Gauge Simulation / Interpolation during Test

    private static func asymptoticPhaseFraction(elapsed: TimeInterval, estimate: TimeInterval) -> Double {
        let ratio = max(0.0, elapsed) / max(4.0, estimate)
        if ratio <= 0.85 {
            return ratio
        }
        return 0.85 + 0.14 * (1.0 - exp(-(ratio - 0.85) * 1.5))
    }

    private static func smoothRemainingSeconds(elapsed: TimeInterval, estimate: TimeInterval) -> TimeInterval {
        let est = max(4.0, estimate)
        let raw = est - elapsed
        if raw >= 4.0 {
            return raw
        }
        let overrun = 4.0 - raw
        return 1.0 + 3.0 * exp(-overrun / 5.0)
    }

    private func startGaugeSimulation() {
        stopGaugeSimulation()
        let startTime = Date()

        gaugeSimulationTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            MainActor.assumeIsolated {
                let now = Date()
                let elapsed = now.timeIntervalSince(startTime)
                let phaseTargetSeconds = Double(self.testDuration.perPhaseSeconds)
                let totalTargetSeconds = Double(self.testDuration.rawValue)
                let uploadBudgetSeconds = max(1.0, totalTargetSeconds - phaseTargetSeconds)

                switch self.phase {
                case .locating, .pinging:
                    self.currentGaugeSpeed = max(0, sin(elapsed * 4) * 5.0)
                    self.testProgress = min(0.06, max(self.testProgress, 0.02 + min(1.0, elapsed / 2.0) * 0.04))
                    let rem = max(1, Int(ceil(max(1.0, totalTargetSeconds - elapsed))))
                    if rem != self.estimatedRemainingSeconds {
                        self.estimatedRemainingSeconds = rem
                    }
                    if now.timeIntervalSince(self.lastDisplayNumberUpdate) >= Self.displayNumberUpdateInterval {
                        self.displayedGaugeSpeed = self.currentGaugeSpeed
                        self.lastDisplayNumberUpdate = now
                    }
                case .downloading:
                    let baseTarget = 65.0 + sin(elapsed * 3.5) * 18.0 + cos(elapsed * 7.0) * 8.0
                    self.currentGaugeSpeed = max(1.0, baseTarget)
                    let dlElapsed = now.timeIntervalSince(self.downloadPhaseStart ?? startTime)
                    let phaseFrac = Self.asymptoticPhaseFraction(elapsed: dlElapsed, estimate: phaseTargetSeconds)
                    self.testProgress = min(0.49, max(self.testProgress, 0.06 + phaseFrac * 0.43))
                    let dlRemaining = Self.smoothRemainingSeconds(elapsed: dlElapsed, estimate: phaseTargetSeconds)
                    let rem = max(1, Int(ceil(dlRemaining + uploadBudgetSeconds)))
                    if rem != self.estimatedRemainingSeconds {
                        self.estimatedRemainingSeconds = rem
                    }
                    if now.timeIntervalSince(self.lastDisplayNumberUpdate) >= Self.displayNumberUpdateInterval {
                        self.displayedGaugeSpeed = self.currentGaugeSpeed
                        self.lastDisplayNumberUpdate = now
                    }
                case .uploading:
                    let baseTarget = 35.0 + sin(elapsed * 4.0) * 10.0 + cos(elapsed * 8.0) * 5.0
                    self.currentGaugeSpeed = max(1.0, baseTarget)
                    let ulElapsed = now.timeIntervalSince(self.uploadPhaseStart ?? startTime)
                    let phaseFrac = Self.asymptoticPhaseFraction(elapsed: ulElapsed, estimate: uploadBudgetSeconds)
                    self.testProgress = min(0.98, max(self.testProgress, 0.50 + phaseFrac * 0.48))
                    let ulRemaining = Self.smoothRemainingSeconds(elapsed: ulElapsed, estimate: uploadBudgetSeconds)
                    let rem = max(1, Int(ceil(ulRemaining)))
                    if rem != self.estimatedRemainingSeconds {
                        self.estimatedRemainingSeconds = rem
                    }
                    if now.timeIntervalSince(self.lastDisplayNumberUpdate) >= Self.displayNumberUpdateInterval {
                        self.displayedGaugeSpeed = self.currentGaugeSpeed
                        self.lastDisplayNumberUpdate = now
                    }
                default:
                    break
                }
            }
        }
    }

    private func stopGaugeSimulation() {
        gaugeSimulationTimer?.invalidate()
        gaugeSimulationTimer = nil
    }

    // MARK: - Process Execution

    nonisolated private static func installTerminationHandler(
        on process: Process,
        executablePath: String,
        resumeGuard: ResumeGuard,
        watchdog: Watchdog,
        group: DispatchGroup,
        outPipe: Pipe,
        errPipe: Pipe,
        outBuffer: OutputBuffer,
        errBuffer: OutputBuffer,
        control: ProcessControl,
        continuation: CheckedContinuation<(String, String), Error>
    ) {
        process.terminationHandler = { proc in
            guard resumeGuard.tryResume() else { return }
            proc.terminationHandler = nil
            watchdog.cancel()

            // Close write ends so readDataToEndOfFile unblocks reliably
            try? outPipe.fileHandleForWriting.close()
            try? errPipe.fileHandleForWriting.close()

            _ = group.wait(timeout: .now() + 2.0)

            let stdOut = String(data: outBuffer.snapshot(), encoding: .utf8) ?? ""
            let stdErr = String(data: errBuffer.snapshot(), encoding: .utf8) ?? ""

            try? outPipe.fileHandleForReading.close()
            try? errPipe.fileHandleForReading.close()

            if control.stopReason == .cancelled {
                continuation.resume(throwing: CancellationError())
            } else if control.stopReason == .timedOut {
                continuation.resume(throwing: NSError(
                    domain: "WarpEngine",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Command timed out."]
                ))
            } else if proc.terminationStatus == 0 {
                continuation.resume(returning: (stdOut, stdErr))
            } else {
                let errMsg = stdErr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? stdOut.trimmingCharacters(in: .whitespacesAndNewlines)
                    : stdErr.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(throwing: NSError(
                    domain: "WarpEngine",
                    code: Int(proc.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: errMsg.isEmpty ? "Process exited with code \(proc.terminationStatus)" : errMsg]
                ))
            }
        }
    }

    private func executeProcess(
        executable: String,
        arguments: [String],
        timeoutSeconds: Double
    ) async throws -> (String, String) {
        // droppykit-lint: allow process: Runs networkQuality CLI tool with deadline and process group cleanup
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        // Inherit path and locale
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
        env["LC_ALL"] = "en_US.UTF-8"
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        let outBuffer = OutputBuffer()
        let errBuffer = OutputBuffer()
        let resumeGuard = ResumeGuard()
        let control = ProcessControl(process: process)
        self.currentControl = control

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(String, String), Error>) in
                let group = DispatchGroup()

                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    outBuffer.append(data)
                    group.leave()
                }

                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                    errBuffer.append(data)
                    group.leave()
                }

                let watchdog = Watchdog(DispatchWorkItem { control.stop(timedOut: true) })

                Self.installTerminationHandler(
                    on: process,
                    executablePath: executable,
                    resumeGuard: resumeGuard,
                    watchdog: watchdog,
                    group: group,
                    outPipe: outPipe,
                    errPipe: errPipe,
                    outBuffer: outBuffer,
                    errBuffer: errBuffer,
                    control: control,
                    continuation: continuation
                )

                do {
                    try control.run()
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: watchdog.workItem)
                } catch {
                    watchdog.cancel()
                    process.terminationHandler = nil
                    try? outPipe.fileHandleForWriting.close()
                    try? errPipe.fileHandleForWriting.close()
                    try? outPipe.fileHandleForReading.close()
                    try? errPipe.fileHandleForReading.close()
                    if resumeGuard.tryResume() {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            control.stop()
        }
    }

    // MARK: - Preferences & History

    private func addHistory(item: WarpHistoryItem) {
        history.insert(item, at: 0)
        if history.count > 25 {
            history = Array(history.prefix(25))
        }
        savePreferences()
    }

    public var onHistoryCleared: (() -> Void)?

    public func clearHistory() {
        history.removeAll()
        lastTelemetry = nil
        currentTelemetry = nil
        currentGaugeSpeed = 0.0
        displayedGaugeSpeed = 0.0
        testProgress = 0.0
        estimatedRemainingSeconds = 0
        phase = .idle
        autoResetTask?.cancel()
        autoResetTask = nil
        if let preferences {
            preferences.setValue(nil as [WarpHistoryItem]?, forKey: "warp.history")
            preferences.setValue(nil as SpeedtestTelemetry?, forKey: "warp.lastTelemetry")
        }
        savePreferences()
        onHistoryCleared?()
    }

    private func loadPreferences() {
        guard let preferences else { return }
        isLoadingPreferences = true
        defer { isLoadingPreferences = false }

        if let unitStr = preferences.value(forKey: "warp.speedUnit", as: String.self),
           let unit = SpeedUnit(rawValue: unitStr) {
            speedUnit = unit
        }
        if let custom = preferences.value(forKey: "warp.customCLIPath", as: String.self) {
            customCLIPath = custom
        }
        if let hud = preferences.value(forKey: "warp.showHUDOnFinish", as: Bool.self) {
            showHUDOnFinish = hud
        }
        if let durVal = preferences.value(forKey: "warp.testDuration", as: Int.self),
           let dur = TestDuration(rawValue: durVal) {
            testDuration = dur
        }
        if let retain = preferences.value(forKey: "warp.retainLastResult", as: Bool.self) {
            retainLastResult = retain
        }
        if let savedHistory = preferences.value(forKey: "warp.history", as: [WarpHistoryItem].self) {
            history = savedHistory
        }
        if let savedTelemetry = preferences.value(forKey: "warp.lastTelemetry", as: SpeedtestTelemetry.self) {
            lastTelemetry = savedTelemetry
        }
        if let savedDlDuration = preferences.value(forKey: "warp.estimatedDownloadDuration", as: Double.self),
           savedDlDuration >= 4.0 && savedDlDuration <= 130.0 {
            estimatedDownloadDuration = savedDlDuration
            hasMeasuredDownload = true
        }
        if let savedUlDuration = preferences.value(forKey: "warp.estimatedUploadDuration", as: Double.self),
           savedUlDuration >= 4.0 && savedUlDuration <= 130.0 {
            estimatedUploadDuration = savedUlDuration
            hasMeasuredUpload = true
        }
        if retainLastResult && currentTelemetry == nil && phase == .idle {
            if let last = resolvedLastTelemetry {
                currentTelemetry = last
                phase = .completed
                currentGaugeSpeed = last.downloadMbps
                displayedGaugeSpeed = last.downloadMbps
                testProgress = 1.0
                estimatedRemainingSeconds = 0
            }
        }
    }

    private func savePreferences() {
        guard !isLoadingPreferences, let preferences else { return }
        preferences.setValue(speedUnit.rawValue, forKey: "warp.speedUnit")
        preferences.setValue(customCLIPath.isEmpty ? nil : customCLIPath, forKey: "warp.customCLIPath")
        preferences.setValue(showHUDOnFinish, forKey: "warp.showHUDOnFinish")
        preferences.setValue(testDuration.rawValue, forKey: "warp.testDuration")
        preferences.setValue(retainLastResult, forKey: "warp.retainLastResult")
        preferences.setValue(history.isEmpty ? nil : history, forKey: "warp.history")
        preferences.setValue(retainLastResult ? (currentTelemetry ?? lastTelemetry) : nil, forKey: "warp.lastTelemetry")
        if hasMeasuredDownload {
            preferences.setValue(estimatedDownloadDuration, forKey: "warp.estimatedDownloadDuration")
        }
        if hasMeasuredUpload {
            preferences.setValue(estimatedUploadDuration, forKey: "warp.estimatedUploadDuration")
        }
    }
}
