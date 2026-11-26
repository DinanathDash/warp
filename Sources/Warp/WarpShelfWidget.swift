//
//  WarpShelfWidget.swift
//  Warp
//

import AppKit
@_weakLinked import DroppyKit
import SwiftUI

public struct WarpShelfWidgetView: View {
    @ObservedObject var engine: WarpEngine
    let context: ShelfWidgetContext
    let onOpenExpanded: () -> Void
    let onOpenSettings: () -> Void

    public static let contentHeight: CGFloat = 160

    public init(
        engine: WarpEngine,
        context: ShelfWidgetContext,
        onOpenExpanded: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.engine = engine
        self.context = context
        self.onOpenExpanded = onOpenExpanded
        self.onOpenSettings = onOpenSettings
    }

    private var dialSize: CGFloat {
        let availableH = context.availableSize.height - (context.contentInsets.top + context.contentInsets.bottom)
        if context.isCompact {
            return max(80, min(availableH - 16, 102))
        }
        if showsResultsOrTesting {
            return max(90, min(availableH - 10, 134))
        } else {
            return max(90, min(availableH - 10, 138))
        }
    }

    private var isTesting: Bool {
        engine.phase.isTesting
    }

    private var showsResultsOrTesting: Bool {
        isTesting || engine.currentTelemetry != nil
    }

    public var body: some View {
        VStack(spacing: 0) {
            if !context.isCompact {
                headerRow
            }

            if context.isCompact {
                pairedBody
            } else {
                soloBody
            }
        }
        .padding(context.contentInsets)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .allowsHitTesting(!context.isShelfTransitioning)
        .onAppear {
            engine.shelfVisibilityDidChange(isVisible: true)
        }
        .onDisappear {
            engine.shelfVisibilityDidChange(isVisible: false)
        }
    }

    @ViewBuilder
    private var headerRow: some View {
        if let wrap = context.notchWrap {
            ShelfWidgetNotchWrapRow(wrap) {
                settingsButton
            } trailing: {
                expandButton
            }
        } else {
            HStack {
                settingsButton
                Spacer(minLength: 0)
                expandButton
            }
            .frame(height: 28)
        }
    }

    private var settingsButton: some View {
        Button {
            onOpenSettings()
        } label: {
            Image(systemName: "gearshape")
        }
        .buttonStyle(
            DroppyWashCircleButtonStyle(
                diameter: context.washControlSize,
                tone: .neutral,
                usesAdaptiveForegrounds: context.usesAdaptiveForegrounds
            )
        )
        .padding(.top, 4)
        .help("Warp settings")
    }

    private var expandButton: some View {
        Button {
            onOpenExpanded()
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
        }
        .buttonStyle(
            DroppyWashCircleButtonStyle(
                diameter: context.washControlSize,
                tone: .neutral,
                usesAdaptiveForegrounds: context.usesAdaptiveForegrounds
            )
        )
        .padding(.top, 4)
        .help("Open full notch speedtest")
    }

    private var soloBody: some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(spacing: DroppySpacing.md) {
                if !showsResultsOrTesting {
                    Spacer(minLength: 0)
                }

                gaugeContainerView

                if showsResultsOrTesting {
                    telemetryCenterView
                        .padding(.leading, 6)
                        .offset(y: -4)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        ))

                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .animation(.spring(response: 0.55, dampingFraction: 0.82), value: showsResultsOrTesting)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsResultsOrTesting {
                bottomActionButton
                    .padding(.bottom, 2)
            }
        }
    }

    private var pairedBody: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)

            gaugeContainerView

            if showsResultsOrTesting {
                HStack(spacing: 8) {
                    Text("↓ \(downloadSpeedText)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(isDownloadPhase ? Color(red: 0.35, green: 0.95, blue: 0.55) : .white)
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Text("↑ \(uploadSpeedText)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(isUploadPhase ? Color(red: 0.85, green: 0.60, blue: 1.0) : .white)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }

                bottomActionButton
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentDisplaySpeed: Double {
        if isTesting {
            return engine.currentGaugeSpeed
        } else if let telemetry = engine.currentTelemetry {
            return telemetry.downloadMbps
        } else {
            return 0.0
        }
    }

    private var gaugeContainerView: some View {
        ZStack {
            WarpGaugeView(
                speedMbps: currentDisplaySpeed,
                phase: isTesting ? engine.phase : (engine.currentTelemetry != nil ? .completed : .idle),
                unit: engine.speedUnit,
                size: dialSize,
                showTicks: true
            )
            .blur(radius: showsResultsOrTesting ? 0 : 2)

            if !showsResultsOrTesting {
                Button {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                        engine.startTest()
                    }
                } label: {
                    Text("GO")
                }
                .buttonStyle(
                    DroppyWashCircleButtonStyle(
                        diameter: dialSize * 0.42,
                        tone: .neutral,
                        glyphSize: max(13, dialSize * 0.14),
                        usesAdaptiveForegrounds: context.usesAdaptiveForegrounds
                    )
                )
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
    }

    private var telemetryCenterView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color(red: 0.35, green: 0.95, blue: 0.55))
                        Text("Download")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                    Text(downloadSpeedText)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(isDownloadPhase ? Color(red: 0.35, green: 0.95, blue: 0.55) : .white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color(red: 0.85, green: 0.60, blue: 1.0))
                        Text("Upload")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                    Text(uploadSpeedText)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(isUploadPhase ? Color(red: 0.85, green: 0.60, blue: 1.0) : .white)
                }
            }

            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    Image(systemName: "gauge.medium")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                    Text(pingText)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.yellow)
                        .monospacedDigit()
                }

                if !serverText.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 10))
                            .foregroundStyle(.teal)
                        Text(serverText)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.teal)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var bottomActionButton: some View {
        Group {
            if isTesting {
                Button("Cancel") {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                        engine.cancelTest()
                    }
                }
                .buttonStyle(
                    DroppyWashPillButtonStyle(
                        height: context.washControlSize,
                        tone: .neutral,
                        usesAdaptiveForegrounds: context.usesAdaptiveForegrounds
                    )
                )
            } else if engine.currentTelemetry != nil {
                Button("Test Again") {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                        engine.startTest()
                    }
                }
                .buttonStyle(
                    DroppyWashPillButtonStyle(
                        height: context.washControlSize,
                        tone: .neutral,
                        usesAdaptiveForegrounds: context.usesAdaptiveForegrounds
                    )
                )
            }
        }
    }

    private var isDownloadPhase: Bool {
        if case .downloading = engine.phase { return true }
        return false
    }

    private var isUploadPhase: Bool {
        if case .uploading = engine.phase { return true }
        return false
    }

    private var downloadSpeedText: String {
        if isDownloadPhase {
            return "--"
        } else if let telemetry = engine.currentTelemetry, telemetry.downloadMbps > 0 {
            return engine.speedUnit.format(mbps: telemetry.downloadMbps)
        } else {
            return "--"
        }
    }

    private var uploadSpeedText: String {
        if isDownloadPhase || isUploadPhase {
            return "--"
        } else if let telemetry = engine.currentTelemetry, telemetry.uploadMbps > 0 {
            return engine.speedUnit.format(mbps: telemetry.uploadMbps)
        } else {
            return "--"
        }
    }

    private var pingText: String {
        if let telemetry = engine.currentTelemetry, telemetry.pingMs > 0, !isDownloadPhase {
            return String(format: "%.0f ms", telemetry.pingMs)
        } else if case .locating = engine.phase {
            return "Finding…"
        } else if case .pinging = engine.phase {
            return "Pinging…"
        } else {
            return "-- ms"
        }
    }

    private var serverText: String {
        if let telemetry = engine.currentTelemetry, !telemetry.serverName.isEmpty {
            return telemetry.serverName
        } else if case .locating = engine.phase {
            return "Locating…"
        } else {
            return ""
        }
    }
}
