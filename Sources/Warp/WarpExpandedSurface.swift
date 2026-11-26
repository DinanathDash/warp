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

    private let bentoCardHeight: CGFloat = 276

    private var isTesting: Bool {
        engine.phase.isTesting
    }

    private var hasResultsOrTesting: Bool {
        isTesting || (engine.currentTelemetry != nil && engine.currentTelemetry!.downloadMbps > 0)
    }

    public var body: some View {
        VStack(spacing: 12) {
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
        .padding(14)
        .frame(width: 560, height: 340)
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
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.needle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(white: 0.82))
                Text("Warp Network Speedtest")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    onOpenSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 24))
                .help("Settings")

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
                .buttonStyle(DroppyCircleButtonStyle(size: 24))
                .help("Collapse to HUD")
            }
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
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            WarpGaugeView(
                speedMbps: 0.0,
                phase: .idle,
                unit: engine.speedUnit,
                size: 190,
                showTicks: true
            )

            Spacer(minLength: 0)

            Button {
                withAnimation(.spring(response: 0.52, dampingFraction: 0.82)) {
                    engine.startTest()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text("Start Speedtest")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(WarpGlassButtonStyle(cornerRadius: 14, tintColor: .cyan))
            .frame(width: 210)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 290, height: bentoCardHeight)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private var leftGaugeBentoCard: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)

            WarpGaugeView(
                speedMbps: currentDisplaySpeed,
                phase: engine.phase.isTesting ? engine.phase : (engine.currentTelemetry != nil ? .completed : .idle),
                unit: engine.speedUnit,
                size: 160,
                showTicks: true
            )

            Spacer(minLength: 0)

            if engine.phase.isTesting {
                Button {
                    engine.cancelTest()
                } label: {
                    Text("Cancel Test")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WarpGlassButtonStyle(cornerRadius: 14))
            } else {
                Button {
                    engine.startTest()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text(engine.currentTelemetry == nil ? "Start Speedtest" : "Run Again")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(WarpGlassButtonStyle(cornerRadius: 14, tintColor: .cyan))

                if let shareURL = engine.currentTelemetry?.shareURL {
                    Button {
                        NSWorkspace.shared.open(shareURL)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share Result")
                        }
                    }
                    .buttonStyle(WarpGlassButtonStyle(cornerRadius: 14))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 220, height: bentoCardHeight)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private var rightBentoColumn: some View {
        activeBentoGrid(telemetry: engine.currentTelemetry)
            .frame(maxWidth: .infinity, maxHeight: bentoCardHeight)
    }

    private func activeBentoGrid(telemetry: SpeedtestTelemetry?) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                bentoTile(
                    title: "Download",
                    value: displayDownloadSpeed,
                    subtitle: isDownloadPhase ? "Testing…" : (telemetry.map { formatBytes($0.bytesReceived) } ?? "--"),
                    icon: "arrow.down.circle.fill",
                    color: Color(red: 0.35, green: 0.95, blue: 0.55)
                )

                bentoTile(
                    title: "Upload",
                    value: displayUploadSpeed,
                    subtitle: (isDownloadPhase || isUploadPhase) ? (isUploadPhase ? "Testing…" : "--") : (telemetry.map { formatBytes($0.bytesSent) } ?? "--"),
                    icon: "arrow.up.circle.fill",
                    color: Color(red: 0.85, green: 0.60, blue: 1.0)
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
                    value: telemetry?.interfaceType ?? "Active Link",
                    subtitle: telemetry?.protocolName.isEmpty == false ? "\(telemetry!.protocolName) · \(telemetry!.clientIP)" : (telemetry?.clientIP ?? "macOS Native"),
                    icon: (telemetry?.interfaceType == "Ethernet") ? "cable.connector" : "wifi",
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
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func bentoServerTile(telemetry: SpeedtestTelemetry?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
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
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
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
        VStack(alignment: .leading, spacing: 3) {
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
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
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

// MARK: - DroppyKit Glass Button Style with Congruent Corner Radius

struct WarpGlassButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 14
    var tintColor: Color? = nil
    var destructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        WarpGlassButtonContent(
            configuration: configuration,
            cornerRadius: cornerRadius,
            tintColor: tintColor,
            destructive: destructive
        )
    }
}

private struct WarpGlassButtonContent: View {
    let configuration: ButtonStyleConfiguration
    let cornerRadius: CGFloat
    let tintColor: Color?
    let destructive: Bool

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    private var fill: DroppyGlassControl.Fill {
        if destructive {
            return .tinted(.red)
        } else if let tintColor {
            return DroppyGlassControl.fill(for: tintColor)
        } else {
            return .veil
        }
    }

    private var shape: AnyShape {
        AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    var body: some View {
        let resolvedFill = fill
        configuration.label
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.9)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DroppyGlassControl.ink(for: resolvedFill, isEnabled: isEnabled))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .droppyGlassControlChrome(
                shape: shape,
                fill: resolvedFill,
                isHovering: isHovering,
                isPressed: configuration.isPressed
            )
            .onHover { isHovering = $0 }
    }
}
