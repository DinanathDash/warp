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

    public var body: some View {
        VStack(spacing: 12) {
            headerBar

            HStack(alignment: .top, spacing: 14) {
                leftGaugeBentoCard
                    .scaleEffect(isCollapsing ? 0.78 : (isMorphedIn ? 1.0 : 0.88), anchor: .top)
                    .offset(y: isCollapsing ? -18 : (isMorphedIn ? 0 : -10))
                    .opacity(isCollapsing ? 0.0 : (isMorphedIn ? 1.0 : 0.0))

                rightBentoColumn
                    .scaleEffect(isCollapsing ? 0.82 : (isMorphedIn ? 1.0 : 0.90), anchor: .top)
                    .offset(y: isCollapsing ? -14 : (isMorphedIn ? 0 : -8))
                    .opacity(isCollapsing ? 0.0 : (isMorphedIn ? 1.0 : 0.0))
            }
        }
        .padding(18)
        .frame(width: 560, height: 410)
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

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 24))
                .help("Close")
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

    private var leftGaugeBentoCard: some View {
        VStack(spacing: 12) {
            statusBadge

            WarpGaugeView(
                speedMbps: currentDisplaySpeed,
                phase: engine.phase.isTesting ? engine.phase : (engine.currentTelemetry != nil ? .completed : .idle),
                unit: engine.speedUnit,
                size: 180,
                showTicks: true
            )
            .padding(.top, 4)

            Spacer(minLength: 0)

            if engine.phase.isTesting {
                Button("Cancel Test") {
                    engine.cancelTest()
                }
                .buttonStyle(DroppyQuietButtonStyle())
                .frame(maxWidth: .infinity)
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
                .buttonStyle(DroppyAccentButtonStyle(color: .cyan))

                if let shareURL = engine.currentTelemetry?.shareURL {
                    Button {
                        NSWorkspace.shared.open(shareURL)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share Result")
                        }
                    }
                    .buttonStyle(DroppyQuietButtonStyle())
                }
            }
        }
        .padding(14)
        .frame(width: 215)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 7, height: 7)

            Text(statusTitle)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private var statusDotColor: Color {
        switch engine.phase {
        case .locating, .pinging:
            return .yellow
        case .downloading:
            return Color(red: 0.35, green: 0.95, blue: 0.55)
        case .uploading:
            return Color(red: 0.85, green: 0.60, blue: 1.0)
        case .completed:
            return Color(red: 0.35, green: 0.95, blue: 0.55)
        case .failed:
            return .red
        case .idle:
            return .cyan
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
        VStack(spacing: 10) {
            if let telemetry = engine.currentTelemetry, telemetry.downloadMbps > 0 {
                activeBentoGrid(telemetry: telemetry)
            } else {
                idleBentoGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func activeBentoGrid(telemetry: SpeedtestTelemetry) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                bentoTile(
                    title: "Download",
                    value: displayDownloadSpeed,
                    subtitle: isDownloadPhase ? "Testing…" : formatBytes(telemetry.bytesReceived),
                    icon: "arrow.down.circle.fill",
                    color: Color(red: 0.35, green: 0.95, blue: 0.55)
                )

                bentoTile(
                    title: "Upload",
                    value: displayUploadSpeed,
                    subtitle: (isDownloadPhase || isUploadPhase) ? (isUploadPhase ? "Testing…" : "--") : formatBytes(telemetry.bytesSent),
                    icon: "arrow.up.circle.fill",
                    color: Color(red: 0.85, green: 0.60, blue: 1.0)
                )
            }

            HStack(spacing: 8) {
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
            }
        }
    }

    private var idleBentoGrid: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
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

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 10))
                        .foregroundStyle(.cyan)
                    Text("Telemetry Capabilities")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.cyan)
                }

                HStack(spacing: 12) {
                    idleCapabilityItem(title: "Throughput", desc: "Download & Upload capacity")
                    idleCapabilityItem(title: "Bufferbloat", desc: "Latency under heavy load")
                    idleCapabilityItem(title: "Responsiveness", desc: "Apple RPM rating")
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))

            if let last = engine.history.first {
                VStack(alignment: .leading, spacing: 6) {
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

                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color(red: 0.35, green: 0.95, blue: 0.55))
                            Text(engine.speedUnit.format(mbps: last.downloadMbps))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color(red: 0.85, green: 0.60, blue: 1.0))
                            Text(engine.speedUnit.format(mbps: last.uploadMbps))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "gauge.medium")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow)
                            Text(String(format: "%.0f ms", last.pingMs))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .monospacedDigit()
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
            } else {
                VStack(alignment: .leading, spacing: 6) {
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
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
            }
        }
    }

    private func idleCapabilityItem(title: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
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
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
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
