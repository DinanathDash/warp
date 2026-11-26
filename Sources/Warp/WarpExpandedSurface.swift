//
//  WarpExpandedSurface.swift
//  Warp
//

import AppKit
@_weakLinked import DroppyKit
import SwiftUI

private struct ExpandedContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

public struct WarpExpandedSurfaceView: View {
    @ObservedObject var engine: WarpEngine
    let onDismiss: () -> Void
    let onCollapse: () -> Void
    let onOpenSettings: () -> Void
    let onMeasuredHeight: ((CGFloat) -> Void)?

    public static let preferredWidth: CGFloat = 584

    @State private var isMorphedIn = false
    @State private var isCollapsing = false

    private static var bentoCardFill: Color { AdaptiveColors.notchSurfaceCardFill }

    public init(
        engine: WarpEngine,
        onDismiss: @escaping () -> Void,
        onCollapse: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onMeasuredHeight: ((CGFloat) -> Void)? = nil
    ) {
        self.engine = engine
        self.onDismiss = onDismiss
        self.onCollapse = onCollapse
        self.onOpenSettings = onOpenSettings
        self.onMeasuredHeight = onMeasuredHeight
    }

    private var hasActiveTelemetry: Bool {
        if let telemetry = engine.currentTelemetry, telemetry.downloadMbps > 0 {
            return true
        }
        return false
    }

    private var hasDiagnosticsTile: Bool {
        guard let telemetry = engine.currentTelemetry, telemetry.downloadMbps > 0 else { return false }
        return telemetry.workingLatencyMs > 0 || telemetry.tcpHandshakeMs > 0
    }

    public var body: some View {
        VStack(spacing: DroppySpacing.md) {
            headerBar

            HStack(alignment: .top, spacing: DroppySpacing.mdl) {
                leftGaugeBentoCard
                    .frame(width: 215)
                    .frame(maxHeight: .infinity)
                    .scaleEffect(isCollapsing ? 0.78 : (isMorphedIn ? 1.0 : 0.88), anchor: .top)
                    .offset(y: isCollapsing ? -18 : (isMorphedIn ? 0 : -10))
                    .opacity(isCollapsing ? 0.0 : (isMorphedIn ? 1.0 : 0.0))

                rightBentoColumn
                    .scaleEffect(isCollapsing ? 0.82 : (isMorphedIn ? 1.0 : 0.90), anchor: .top)
                    .offset(y: isCollapsing ? -14 : (isMorphedIn ? 0 : -8))
                    .opacity(isCollapsing ? 0.0 : (isMorphedIn ? 1.0 : 0.0))
            }
            .fixedSize(horizontal: false, vertical: true)
            .animation(.spring(response: 0.42, dampingFraction: 0.84), value: hasActiveTelemetry)
            .animation(.spring(response: 0.42, dampingFraction: 0.84), value: hasDiagnosticsTile)
        }
        .frame(width: Self.preferredWidth, alignment: .top)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: ExpandedContentHeightKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(ExpandedContentHeightKey.self) { height in
            guard height > 0 else { return }
            onMeasuredHeight?(height)
        }
        .frame(maxHeight: .infinity, alignment: .top)
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
        HStack(spacing: DroppySpacing.sm) {
            Spacer()

            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(DroppyWashCircleButtonStyle(diameter: 26, tone: .neutral, glyphSize: 11))
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

    private var currentReadoutSpeed: Double {
        if engine.phase.isTesting {
            return engine.displayedGaugeSpeed
        } else if let telemetry = engine.currentTelemetry, telemetry.downloadMbps > 0 {
            return telemetry.downloadMbps
        } else {
            return 0.0
        }
    }

    private var leftGaugeBentoCard: some View {
        VStack(spacing: DroppySpacing.smd) {
            statusBadge

            GeometryReader { geo in
                let dialSize = max(84, min(geo.size.width, geo.size.height))
                WarpGaugeView(
                    speedMbps: currentDisplaySpeed,
                    phase: engine.phase.isTesting ? engine.phase : (engine.currentTelemetry != nil ? .completed : .idle),
                    unit: engine.speedUnit,
                    size: dialSize,
                    showTicks: true,
                    progress: engine.testProgress,
                    onRaisedCard: true
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .frame(minHeight: 104, maxHeight: .infinity)

            HStack(alignment: .firstTextBaseline, spacing: DroppySpacing.xs) {
                Text(engine.speedUnit.formatValueOnly(mbps: currentReadoutSpeed))
                    .font(.system(size: 19, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: currentReadoutSpeed))
                    .animation(.smooth(duration: 0.3), value: currentReadoutSpeed)
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)

                Text(engine.speedUnit.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
            }

            if engine.phase.isTesting {
                Button {
                    engine.cancelTest()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Cancel Test")
                            .font(.system(size: 13, weight: .semibold))
                    }
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
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .buttonStyle(DroppyWashPillButtonStyle(height: DroppyWashSize.solo, tone: .accent(.green), fillsWidth: true, usesAdaptiveForegrounds: false))

                if let shareURL = engine.currentTelemetry?.shareURL {
                    Button {
                        NSWorkspace.shared.open(shareURL)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Share Result")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .buttonStyle(DroppyWashPillButtonStyle(height: 28, tone: .neutral, fillsWidth: true, usesAdaptiveForegrounds: false))
                }
            }
        }
        .padding(DroppySpacing.mdl)
        .background(
            RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous)
                .fill(Self.bentoCardFill)
        )
    }

    private var statusBadge: some View {
        Text(statusTitle)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(statusTintColor)
            .lineLimit(1)
            .padding(.horizontal, DroppySpacing.smd)
            .padding(.vertical, DroppySpacing.xs)
            .background(Capsule(style: .continuous).fill(statusTintColor.opacity(0.16)))
    }

    private var statusTintColor: Color {
        switch engine.phase {
        case .locating, .pinging:
            return .yellow
        case .downloading, .completed:
            return .green
        case .uploading:
            return .purple
        case .failed:
            return .red
        case .idle:
            return AdaptiveColors.notchSurfaceSecondaryText
        }
    }

    private var statusTitle: String {
        switch engine.phase {
        case .locating: return "Locating server"
        case .pinging: return "Testing ping"
        case .downloading: return "Testing download"
        case .uploading: return "Testing upload"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .idle: return "Ready"
        }
    }

    private var rightBentoColumn: some View {
        VStack(spacing: DroppySpacing.smd) {
            if let telemetry = engine.currentTelemetry, telemetry.downloadMbps > 0 {
                activeBentoGrid(telemetry: telemetry)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            } else {
                idleBentoGrid
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func activeBentoGrid(telemetry: SpeedtestTelemetry) -> some View {
        VStack(spacing: DroppySpacing.smd) {
            HStack(spacing: DroppySpacing.smd) {
                bentoTile(
                    title: "Download",
                    value: displayDownloadSpeed,
                    subtitle: isDownloadPhase ? "Testing…" : formatBytes(telemetry.bytesReceived),
                    icon: "arrow.down.circle.fill",
                    color: .green,
                    valueColor: displayDownloadSpeed == "--" ? AdaptiveColors.notchSurfacePrimaryText : .green
                )

                bentoTile(
                    title: "Upload",
                    value: displayUploadSpeed,
                    subtitle: (isDownloadPhase || isUploadPhase) ? (isUploadPhase ? "Testing…" : "--") : formatBytes(telemetry.bytesSent),
                    icon: "arrow.up.circle.fill",
                    color: .purple,
                    valueColor: displayUploadSpeed == "--" ? AdaptiveColors.notchSurfacePrimaryText : .purple
                )
            }

            HStack(spacing: DroppySpacing.smd) {
                bentoTile(
                    title: "Latency",
                    value: String(format: "%.1f ms", telemetry.pingMs),
                    subtitle: telemetry.responsivenessRPM > 0
                        ? String(format: "%.0f RPM (%@)", telemetry.responsivenessRPM, rpmRating(telemetry.responsivenessRPM))
                        : "Base RTT",
                    icon: "gauge.medium",
                    color: .yellow
                )

                bentoTile(
                    title: "Connection",
                    value: telemetry.interfaceType,
                    subtitle: telemetry.protocolName.isEmpty ? telemetry.clientIP : "\(telemetry.protocolName) · \(telemetry.clientIP)",
                    icon: telemetry.interfaceType == "Ethernet" ? "cable.connector" : "wifi",
                    color: .secondary
                )
            }

            bentoServerTile(telemetry: telemetry)

            if telemetry.workingLatencyMs > 0 || telemetry.tcpHandshakeMs > 0 {
                bentoDiagnosticsTile(telemetry: telemetry)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var idleBentoGrid: some View {
        VStack(spacing: DroppySpacing.smd) {
            HStack(spacing: DroppySpacing.smd) {
                bentoTile(
                    title: "Engine",
                    value: "Apple CDN",
                    subtitle: "macOS networkQuality",
                    icon: "apple.logo",
                    color: .cyan
                )

                bentoTile(
                    title: "Link",
                    value: engine.history.first?.clientISP ?? "Active Interface",
                    subtitle: "Zero overhead · Native",
                    icon: "network",
                    color: .secondary
                )
            }

            VStack(alignment: .leading, spacing: DroppySpacing.xsm) {
                HStack(spacing: 5) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 10))
                        .foregroundStyle(.cyan)
                    Text("Telemetry Capabilities")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.cyan)
                }

                HStack(alignment: .top, spacing: DroppySpacing.md) {
                    idleCapabilityItem(title: "Throughput", desc: "Download & Upload capacity")
                    idleCapabilityItem(title: "Bufferbloat", desc: "Latency under heavy load")
                    idleCapabilityItem(title: "Responsiveness", desc: "Apple RPM rating")
                }
            }
            .padding(DroppySpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DroppyRadius.ms, style: .continuous).fill(Self.bentoCardFill))

            if let last = engine.history.first {
                VStack(alignment: .leading, spacing: DroppySpacing.xsm) {
                    HStack {
                        HStack(spacing: 5) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 10))
                                .foregroundStyle(.yellow)
                            Text("Last Recorded Test")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(.yellow)
                        }
                        Spacer()
                        Text(last.timestamp.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: DroppySpacing.lg) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.green)
                            Text(engine.speedUnit.format(mbps: last.downloadMbps))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.green)
                                .monospacedDigit()
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.purple)
                            Text(engine.speedUnit.format(mbps: last.uploadMbps))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.purple)
                                .monospacedDigit()
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "gauge.medium")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow)
                            Text(String(format: "%.0f ms", last.pingMs))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                                .monospacedDigit()
                        }
                    }
                }
                .padding(DroppySpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: DroppyRadius.ms, style: .continuous).fill(Self.bentoCardFill))
            } else {
                VStack(alignment: .leading, spacing: DroppySpacing.xsm) {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.shield.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.teal)
                        Text("Ready to Benchmark")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(.teal)
                    }
                    Text("Click Start Speedtest to measure bidirectional bandwidth, loaded latency, and network responsiveness against Apple's edge servers.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DroppySpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: DroppyRadius.ms, style: .continuous).fill(Self.bentoCardFill))
            }
        }
    }

    private func idleCapabilityItem(title: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(desc)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bentoTile(
        title: String,
        value: String,
        subtitle: String,
        icon: String,
        color: Color,
        valueColor: Color = AdaptiveColors.notchSurfacePrimaryText
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
        .padding(DroppySpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DroppyRadius.ms, style: .continuous).fill(Self.bentoCardFill))
    }

    private func bentoServerTile(telemetry: SpeedtestTelemetry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "server.rack")
                    .font(.system(size: 10))
                    .foregroundStyle(.teal)
                Text("Server")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.teal)
            }
            Text(telemetry.serverSponsor.isEmpty ? (telemetry.serverName.isEmpty ? "Apple Edge CDN" : telemetry.serverName) : telemetry.serverSponsor)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Text(telemetry.serverHost.isEmpty ? telemetry.serverName : telemetry.serverHost)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(DroppySpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DroppyRadius.ms, style: .continuous).fill(Self.bentoCardFill))
    }

    private func bentoDiagnosticsTile(telemetry: SpeedtestTelemetry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 10))
                    .foregroundStyle(.cyan)
                Text("Loaded Latency & Handshake")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.cyan)
            }
            if telemetry.workingLatencyMs > 0 {
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
            }
            if telemetry.tcpHandshakeMs > 0 {
                HStack(spacing: 4) {
                    Text("Handshakes:")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.secondary)
                    Text(String(format: "TCP %.0f ms · TLS %.0f ms", telemetry.tcpHandshakeMs, telemetry.tlsHandshakeMs))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(DroppySpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DroppyRadius.ms, style: .continuous).fill(Self.bentoCardFill))
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
