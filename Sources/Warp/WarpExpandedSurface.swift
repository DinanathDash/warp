//
//  WarpExpandedSurface.swift
//  Warp
//

import AppKit
@_weakLinked import DroppyKit
import SwiftUI

public struct WarpExpandedSurfaceView: View {
    @ObservedObject var engine: WarpEngine
    let onDismiss: () -> Void
    let onCollapse: () -> Void
    let onOpenSettings: () -> Void

    @State private var isMorphedIn = false
    @State private var isCollapsing = false

    public init(
        engine: WarpEngine,
        onDismiss: @escaping () -> Void,
        onCollapse: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.engine = engine
        self.onDismiss = onDismiss
        self.onCollapse = onCollapse
        self.onOpenSettings = onOpenSettings
    }

    private let bentoCardHeight: CGFloat = 210

    private var isTesting: Bool {
        engine.phase.isTesting
    }

    private var hasResultsOrTesting: Bool {
        isTesting || (engine.currentTelemetry != nil && engine.currentTelemetry!.downloadMbps > 0)
    }

    public var body: some View {
        VStack(spacing: 8) {
            headerBar

            Group {
                if hasResultsOrTesting {
                    HStack(alignment: .top, spacing: 14) {
                        leftGaugeBentoCard
                        rightBentoColumn
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
                } else {
                    freshCenterView
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.95).combined(with: .opacity),
                            removal: .scale(scale: 0.95).combined(with: .opacity)
                        ))
                }
            }
            .scaleEffect(isCollapsing ? 0.80 : (isMorphedIn ? 1.0 : 0.88), anchor: .top)
            .offset(y: isCollapsing ? -18 : (isMorphedIn ? 0 : -10))
            .opacity(isCollapsing ? 0.0 : (isMorphedIn ? 1.0 : 0.0))
        }
        .padding(12)
        .frame(width: 520, height: 268)
        .animation(.spring(response: 0.52, dampingFraction: 0.82), value: hasResultsOrTesting)
        .onAppear {
            engine.expandedVisibilityDidChange(isVisible: true)
            withAnimation(.spring(response: 0.44, dampingFraction: 0.78)) {
                isMorphedIn = true
            }
        }
        .onDisappear {
            engine.expandedVisibilityDidChange(isVisible: false)
        }
    }

    private var headerBar: some View {
        HStack {
            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(DroppyWashCircleButtonStyle(diameter: 26, tone: .neutral, glyphSize: 11))
            .help("Settings")

            Spacer()

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    isCollapsing = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                    onCollapse()
                }
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(DroppyWashCircleButtonStyle(diameter: 26, tone: .neutral, glyphSize: 10))
            .help("Collapse to HUD")
        }
    }

    private var currentDisplaySpeed: Double {
        if engine.phase.isTesting {
            return engine.currentGaugeSpeed
        } else if let telemetry = engine.currentTelemetry, telemetry.downloadMbps > 0 {
            return telemetry.downloadMbps
        } else {
            return 0.0
        }
    }

    private var freshCenterView: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            WarpGaugeView(
                speedMbps: 0.0,
                phase: .idle,
                unit: engine.speedUnit,
                size: 148,
                showTicks: false,
                interfaceIcon: engine.activeInterfaceIcon,
                onRaisedCard: true
            )

            Spacer(minLength: 0)

            Button {
                withAnimation(.spring(response: 0.52, dampingFraction: 0.82)) {
                    engine.startTest()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Start Speedtest")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(DroppyWashPillButtonStyle(height: DroppyWashSize.solo, tone: .accent(.cyan), fillsWidth: true, usesAdaptiveForegrounds: false))
            .frame(width: 180)

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 260, height: bentoCardHeight)
    }

    private var leftGaugeBentoCard: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)

            WarpGaugeView(
                speedMbps: currentDisplaySpeed,
                phase: engine.phase.isTesting ? engine.phase : (engine.currentTelemetry != nil ? .completed : .idle),
                unit: engine.speedUnit,
                size: 144,
                showTicks: false,
                progress: engine.testProgress,
                interfaceIcon: engine.activeInterfaceIcon,
                onRaisedCard: true
            )

            Spacer(minLength: 0)

            if engine.phase.isTesting {
                Button {
                    engine.cancelTest()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Cancel Test")
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(DroppyWashPillButtonStyle(height: DroppyWashSize.solo, tone: .neutral, fillsWidth: true, usesAdaptiveForegrounds: false))
            } else {
                Button {
                    engine.startTest()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(engine.currentTelemetry == nil ? "Start Speedtest" : "Run Again")
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(DroppyWashPillButtonStyle(height: DroppyWashSize.solo, tone: .accent(.cyan), fillsWidth: true, usesAdaptiveForegrounds: false))

                if let shareURL = engine.currentTelemetry?.shareURL {
                    Button {
                        NSWorkspace.shared.open(shareURL)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Share Result")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                    }
                    .buttonStyle(DroppyWashPillButtonStyle(height: 26, tone: .neutral, fillsWidth: true, usesAdaptiveForegrounds: false))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: 200, height: bentoCardHeight)
    }

    private var rightBentoColumn: some View {
        activeBentoGrid(telemetry: engine.currentTelemetry)
            .frame(maxWidth: .infinity, maxHeight: bentoCardHeight)
    }

    private func activeBentoGrid(telemetry: SpeedtestTelemetry?) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                bentoTile(
                    title: "Download",
                    value: displayDownloadSpeed,
                    subtitle: isDownloadPhase ? "Testing…" : (telemetry.map { formatBytes($0.bytesReceived) } ?? "--"),
                    icon: "arrow.down.circle.fill",
                    color: .green,
                    valueColor: displayDownloadSpeed == "--" ? AdaptiveColors.notchSurfacePrimaryText : .green
                )

                bentoTile(
                    title: "Upload",
                    value: displayUploadSpeed,
                    subtitle: (isDownloadPhase || isUploadPhase) ? (isUploadPhase ? "Testing…" : "--") : (telemetry.map { formatBytes($0.bytesSent) } ?? "--"),
                    icon: "arrow.up.circle.fill",
                    color: .purple,
                    valueColor: displayUploadSpeed == "--" ? AdaptiveColors.notchSurfacePrimaryText : .purple
                )
            }

            HStack(spacing: 8) {
                bentoTile(
                    title: "Latency",
                    value: latencyValueText(telemetry: telemetry),
                    subtitle: latencySubtitleText(telemetry: telemetry),
                    icon: "gauge.medium",
                    color: .yellow
                )

                bentoTile(
                    title: "Connection",
                    value: telemetry?.interfaceType ?? engine.primaryInterfaceType.rawValue,
                    subtitle: telemetry?.protocolName.isEmpty == false ? "\(telemetry!.protocolName) · \(telemetry!.clientIP)" : (telemetry?.clientIP ?? "macOS Native"),
                    icon: engine.activeInterfaceIcon,
                    color: .secondary
                )
            }

            bentoServerTile(telemetry: telemetry)

            bentoDiagnosticsTile(telemetry: telemetry)
        }
    }

    private func latencyValueText(telemetry: SpeedtestTelemetry?) -> String {
        if let telemetry, telemetry.pingMs > 0, !isDownloadPhase {
            return String(format: "%.1f ms", telemetry.pingMs)
        } else if case .locating = engine.phase {
            return "Finding…"
        } else if case .pinging = engine.phase {
            return "Pinging…"
        } else {
            return "-- ms"
        }
    }

    private func latencySubtitleText(telemetry: SpeedtestTelemetry?) -> String {
        guard let telemetry else { return "Base RTT" }
        return telemetry.responsivenessRPM > 0
            ? String(format: "%.0f RPM (%@)", telemetry.responsivenessRPM, rpmRating(telemetry.responsivenessRPM))
            : "Base RTT"
    }

    private func bentoTile(
        title: String,
        value: String,
        subtitle: String,
        icon: String,
        color: Color,
        valueColor: Color = AdaptiveColors.notchSurfacePrimaryText
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.3), value: value)
                .foregroundStyle(valueColor)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, DroppySpacing.sm)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bentoServerTile(telemetry: SpeedtestTelemetry?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "server.rack")
                    .font(.system(size: 10))
                    .foregroundStyle(.teal)
                Text("Server")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.teal)
            }
            Text(serverTitleText(telemetry: telemetry))
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Text(serverSubtitleText(telemetry: telemetry))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, DroppySpacing.sm)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func serverTitleText(telemetry: SpeedtestTelemetry?) -> String {
        if let telemetry, !telemetry.serverSponsor.isEmpty {
            return telemetry.serverSponsor
        } else if let telemetry, !telemetry.serverName.isEmpty {
            return telemetry.serverName
        } else if case .locating = engine.phase {
            return "Locating server…"
        } else {
            return "Apple Edge CDN"
        }
    }

    private func serverSubtitleText(telemetry: SpeedtestTelemetry?) -> String {
        if let telemetry, !telemetry.serverHost.isEmpty {
            return telemetry.serverHost
        } else if let telemetry, !telemetry.serverName.isEmpty {
            return telemetry.serverName
        } else {
            return "macOS networkQuality"
        }
    }

    private func bentoDiagnosticsTile(telemetry: SpeedtestTelemetry?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 10))
                    .foregroundStyle(.cyan)
                Text("Loaded Latency & Handshake")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.cyan)
            }
            if let telemetry, telemetry.workingLatencyMs > 0 {
                HStack(spacing: 4) {
                    Text("Bufferbloat latency:")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.0f ms under load", telemetry.workingLatencyMs))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.smooth(duration: 0.3), value: telemetry.workingLatencyMs)
                }
            } else if let telemetry, telemetry.tcpHandshakeMs > 0 {
                HStack(spacing: 4) {
                    Text("Handshakes:")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.secondary)
                    Text(String(format: "TCP %.0f ms · TLS %.0f ms", telemetry.tcpHandshakeMs, telemetry.tlsHandshakeMs))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else {
                Text(isTesting ? "Evaluating loaded latency…" : "Standard responsiveness benchmark")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, DroppySpacing.sm)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rpmRating(_ rpm: Double) -> String {
        if rpm >= 1200 { return "High" }
        if rpm >= 400 { return "Medium" }
        return "Low"
    }

    private var isDownloadPhase: Bool {
        if case .downloading = engine.phase { return true }
        return false
    }

    private var isUploadPhase: Bool {
        if case .uploading = engine.phase { return true }
        return false
    }

    private var displayDownloadSpeed: String {
        if isDownloadPhase {
            return "--"
        } else if let telemetry = engine.currentTelemetry, telemetry.downloadMbps > 0 {
            return engine.speedUnit.format(mbps: telemetry.downloadMbps)
        } else {
            return "--"
        }
    }

    private var displayUploadSpeed: String {
        if isDownloadPhase || isUploadPhase {
            return "--"
        } else if let telemetry = engine.currentTelemetry, telemetry.uploadMbps > 0 {
            return engine.speedUnit.format(mbps: telemetry.uploadMbps)
        } else {
            return "--"
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 MB" }
        let mb = Double(bytes) / 1_048_576.0
        if mb >= 1024 {
            return String(format: "%.2f GB", mb / 1024.0)
        }
        return String(format: "%.1f MB", mb)
    }
}
