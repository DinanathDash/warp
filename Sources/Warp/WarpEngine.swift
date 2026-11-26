//
//  WarpEngine.swift
//  Warp
//

import AppKit
import Combine
@_weakLinked import DroppyKit
import Foundation
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
    @Published public private(set) var phase: SpeedtestPhase = .idle
    @Published public private(set) var currentTelemetry: SpeedtestTelemetry?
    @Published public private(set) var currentGaugeSpeed: Double = 0.0
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

    public static let defaultNativeExecutable = "/usr/bin/networkQuality"
    @Published public private(set) var detectedCLIPath: String?

    public var isNativeEngine: Bool {
        detectedCLIPath == Self.defaultNativeExecutable
    }

    private var activeTestTask: Task<Void, Never>?
    private var gaugeSimulationTimer: Timer?
    private var currentControl: ProcessControl?
    private weak var preferences: (any DropletPreferencesService)?

    public init() {
        detectCLI()
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

        activeTestTask = Task { [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()

                self.phase = .locating
                self.startGaugeSimulation()

                self.phase = .downloading(currentMbps: 1.0)
                let (dlStdout, _) = try await self.executeProcess(
                    executable: cliPath,
                    arguments: ["-c", "-v", "-u"],
                    timeoutSeconds: 35
                )

                try Task.checkCancellation()

                guard let dlJsonData = dlStdout.data(using: .utf8) else {
                    throw NSError(domain: "WarpEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to read download test output."])
                }

                let decoder = JSONDecoder()
                let dlOutput = try decoder.decode(NetworkQualityOutput.self, from: dlJsonData)
                let dlTelemetry = dlOutput.toTelemetry()

                self.currentTelemetry = dlTelemetry
                self.currentGaugeSpeed = dlTelemetry.downloadMbps
                WarpLog.info("Download completed: \(dlTelemetry.downloadMbps) Mbps, Ping \(dlTelemetry.pingMs) ms")

                self.phase = .uploading(currentMbps: 1.0)

                let (ulStdout, _) = try await self.executeProcess(
                    executable: cliPath,
                    arguments: ["-c", "-v", "-d"],
                    timeoutSeconds: 35
                )

                try Task.checkCancellation()

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
                self.currentTelemetry = finalTelemetry
                self.currentGaugeSpeed = finalTelemetry.downloadMbps
                self.phase = .completed

                WarpLog.info("Network test completed: DL \(finalTelemetry.downloadMbps) Mbps, UL \(finalTelemetry.uploadMbps) Mbps, Ping \(finalTelemetry.pingMs) ms, RPM \(finalTelemetry.responsivenessRPM)")
                self.addHistory(item: WarpHistoryItem(telemetry: finalTelemetry))
                self.handleVisibilityChange()
            } catch is CancellationError {
                self.stopGaugeSimulation()
                self.phase = .idle
                self.currentGaugeSpeed = 0.0
                WarpLog.info("Speedtest cancelled")
            } catch {
                self.stopGaugeSimulation()
                let errMessage = error.localizedDescription
                WarpLog.error("Speedtest failed: \(errMessage)")
                self.phase = .failed(errMessage)
                self.currentGaugeSpeed = 0.0
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
        guard !isShelfVisible && !isExpandedVisible else { return }
        autoResetTask?.cancel()
        autoResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 14_000_000_000)
            guard !Task.isCancelled, let self, self.phase == .completed else { return }
            guard !self.isShelfVisible && !self.isExpandedVisible else { return }
            self.phase = .idle
            self.currentTelemetry = nil
            self.currentGaugeSpeed = 0.0
            WarpLog.info("Shelf result auto-dismissed back to idle while out of view")
        }
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
        WarpLog.info("Test stopped by user")
    }

    // MARK: - Gauge Simulation / Interpolation during Test

    private func startGaugeSimulation() {
        stopGaugeSimulation()
        let startTime = Date()

        gaugeSimulationTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            MainActor.assumeIsolated {
                let elapsed = Date().timeIntervalSince(startTime)
                switch self.phase {
                case .locating, .pinging:
                    self.currentGaugeSpeed = max(0, sin(elapsed * 4) * 5.0)
                case .downloading:
                    let baseTarget = 65.0 + sin(elapsed * 3.5) * 18.0 + cos(elapsed * 7.0) * 8.0
                    self.currentGaugeSpeed = max(1.0, baseTarget)
                case .uploading:
                    let baseTarget = 35.0 + sin(elapsed * 4.0) * 10.0 + cos(elapsed * 8.0) * 5.0
                    self.currentGaugeSpeed = max(1.0, baseTarget)
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

    public func clearHistory() {
        history.removeAll()
        savePreferences()
    }

    private func loadPreferences() {
        guard let preferences else { return }
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
        if let savedHistory = preferences.value(forKey: "warp.history", as: [WarpHistoryItem].self) {
            history = savedHistory
        }
    }

    private func savePreferences() {
        guard let preferences else { return }
        preferences.setValue(speedUnit.rawValue, forKey: "warp.speedUnit")
        preferences.setValue(customCLIPath.isEmpty ? nil : customCLIPath, forKey: "warp.customCLIPath")
        preferences.setValue(showHUDOnFinish, forKey: "warp.showHUDOnFinish")
        preferences.setValue(history.isEmpty ? nil : history, forKey: "warp.history")
    }
}
