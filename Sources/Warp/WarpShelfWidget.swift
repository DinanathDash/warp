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

    public static let contentHeight: CGFloat = 288
    public static let preferredSoloWidth: CGFloat = 152
    public static let preferredPairedWidth: CGFloat = 144
    public static let minimumWidth: CGFloat = 140
    public static let pairWeight: Double = 0.62

    private static let bottomControlHeight: CGFloat = DroppyWashSize.solo

    @State private var didCopy = false
    @State private var copyFeedbackTask: Task<Void, Never>?

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

    private var isTesting: Bool {
        engine.phase.isTesting
    }

    private var isDownloadPhase: Bool {
        if case .downloading = engine.phase { return true }
        return false
    }

    private var isUploadPhase: Bool {
        if case .uploading = engine.phase { return true }
        return false
    }

    private var primaryInk: Color {
        context.usesAdaptiveForegrounds ? AdaptiveColors.primaryTextAuto : AdaptiveColors.notchSurfacePrimaryText
    }

    private var secondaryInk: Color {
        context.usesAdaptiveForegrounds ? AdaptiveColors.secondaryTextAuto : AdaptiveColors.notchSurfaceTertiaryText
    }

    private var currentDisplaySpeed: Double {
        if isTesting {
            return engine.currentGaugeSpeed
        }
        if let stats = engine.latestRecordedStats {
            return stats.downloadMbps
        }
        return 0.0
    }

    private var gaugePhase: SpeedtestPhase {
        if isTesting {
            return engine.phase
        }
        if engine.currentTelemetry != nil {
            return .completed
        }
        return .idle
    }

    public var body: some View {
        GeometryReader { geometry in
            let isSpacious = !context.isCompact
            let sideMargin: CGFloat = isSpacious ? DroppySpacing.lg : 0
            let columnWidth = isSpacious
                ? min(geometry.size.width - sideMargin * 2, 224)
                : geometry.size.width
            let topDialClearance: CGFloat = isSpacious ? DroppySpacing.xs : 10
            let statsReserve: CGFloat = isSpacious ? 46 : 38
            let reservedVertical: CGFloat = topDialClearance + DroppySpacing.sm + statsReserve + DroppySpacing.smd + Self.bottomControlHeight
            let dialSize = max(96, min(columnWidth, geometry.size.height - reservedVertical))
            let expandDiameter: CGFloat = isSpacious ? DroppyWashSize.paired : DroppyWashSize.row

            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    Button(action: onOpenExpanded) {
                        WarpGaugeView(
                            speedMbps: currentDisplaySpeed,
                            phase: gaugePhase,
                            unit: engine.speedUnit,
                            size: dialSize,
                            showTicks: true,
                            progress: engine.testProgress,
                            usesAdaptiveForegrounds: context.usesAdaptiveForegrounds
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, topDialClearance)
                    .help("Open expanded speedtest")
                    .accessibilityLabel("Open expanded speedtest")

                    Spacer(minLength: DroppySpacing.sm)

                    previousStatsView(isSpacious: isSpacious)

                    Spacer(minLength: DroppySpacing.smd)

                    bottomActionRow(isSpacious: isSpacious)
                }
                .frame(width: columnWidth, height: geometry.size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                Button(action: onOpenExpanded) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(
                    DroppyWashCircleButtonStyle(
                        diameter: expandDiameter,
                        tone: .neutral,
                        usesAdaptiveForegrounds: context.usesAdaptiveForegrounds
                    )
                )
                .help("Open expanded bento view")
                .accessibilityLabel("Open expanded bento view")
            }
        }
        .padding(context.contentInsets)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .allowsHitTesting(!context.isShelfTransitioning)
        .onAppear {
            engine.shelfVisibilityDidChange(isVisible: true)
        }
        .onDisappear {
            copyFeedbackTask?.cancel()
            engine.shelfVisibilityDidChange(isVisible: false)
        }
    }

    private func previousStatsView(isSpacious: Bool) -> some View {
        VStack(spacing: isSpacious ? 4 : 3) {
            HStack(spacing: isSpacious ? DroppySpacing.xl : DroppySpacing.smd) {
                HStack(alignment: .firstTextBaseline, spacing: isSpacious ? 4 : 3) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: isSpacious ? 12 : 9, weight: .bold))
                        .foregroundStyle(.green)

                    Text(downloadValueText)
                        .font(.system(size: isSpacious ? 21 : 14, weight: .bold))
                        .foregroundStyle(hasDownloadValue ? .green : primaryInk)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: downloadNumericValue))
                        .animation(.smooth(duration: 0.3), value: downloadValueText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if hasDownloadValue {
                        Text(engine.speedUnit.rawValue)
                            .font(.system(size: isSpacious ? 11 : 9, weight: .semibold))
                            .foregroundStyle(Color.green.opacity(0.82))
                            .lineLimit(1)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: isSpacious ? 4 : 3) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: isSpacious ? 12 : 9, weight: .bold))
                        .foregroundStyle(.purple)

                    Text(uploadValueText)
                        .font(.system(size: isSpacious ? 21 : 14, weight: .bold))
                        .foregroundStyle(hasUploadValue ? .purple : primaryInk)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: uploadNumericValue))
                        .animation(.smooth(duration: 0.3), value: uploadValueText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if hasUploadValue {
                        Text(engine.speedUnit.rawValue)
                            .font(.system(size: isSpacious ? 11 : 9, weight: .semibold))
                            .foregroundStyle(Color.purple.opacity(0.82))
                            .lineLimit(1)
                    }
                }
            }

            HStack(spacing: 4) {
                if isTesting {
                    Text(liveTestingStatusText)
                        .font(.system(size: isSpacious ? 11 : 10, weight: .medium))
                        .foregroundStyle(secondaryInk)
                        .lineLimit(1)

                    if engine.estimatedRemainingSeconds > 0 {
                        Text("·")
                            .font(.system(size: isSpacious ? 11 : 10, weight: .medium))
                            .foregroundStyle(secondaryInk)

                        Text(remainingTimeText)
                            .font(.system(size: isSpacious ? 11 : 10, weight: .medium))
                            .foregroundStyle(secondaryInk)
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.smooth(duration: 0.3), value: engine.estimatedRemainingSeconds)
                            .lineLimit(1)
                    }
                } else {
                    Image(systemName: "gauge.medium")
                        .font(.system(size: isSpacious ? 10 : 9, weight: .medium))
                        .foregroundStyle(secondaryInk)
                    Text(pingText)
                        .font(.system(size: isSpacious ? 11 : 10, weight: .medium))
                        .foregroundStyle(secondaryInk)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: pingNumericValue))
                        .animation(.smooth(duration: 0.3), value: pingText)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func bottomActionRow(isSpacious: Bool) -> some View {
        HStack(spacing: isSpacious ? DroppySpacing.sm : DroppySpacing.xsm) {
            Button {
                copyLatestStats()
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 14.5, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(
                DroppyWashCircleButtonStyle(
                    diameter: Self.bottomControlHeight,
                    tone: didCopy ? .accent(.green) : .neutral,
                    glyphSize: 14.5,
                    usesAdaptiveForegrounds: context.usesAdaptiveForegrounds
                )
            )
            .animation(.smooth(duration: 0.25), value: didCopy)
            .disabled(engine.latestRecordedStats == nil)
            .help(didCopy ? "Copied" : "Copy test results")
            .accessibilityLabel("Copy test results")

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                    if isTesting {
                        engine.cancelTest()
                    } else {
                        engine.startTest()
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isTesting ? "stop.fill" : "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                    Text(isTesting ? "Cancel" : "Test Again")
                        .font(.system(size: isSpacious ? 14 : 13, weight: .semibold))
                }
            }
            .buttonStyle(
                DroppyWashPillButtonStyle(
                    height: Self.bottomControlHeight,
                    tone: .neutral,
                    fillsWidth: true,
                    usesAdaptiveForegrounds: context.usesAdaptiveForegrounds
                )
            )
        }
    }

    private func copyLatestStats() {
        guard let text = engine.formattedLatestStatsForClipboard else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        copyFeedbackTask?.cancel()
        withAnimation(.smooth(duration: 0.25)) {
            didCopy = true
        }
        copyFeedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.28)) {
                didCopy = false
            }
        }
    }

    private var liveTestingStatusText: String {
        switch engine.phase {
        case .locating:
            return "Locating"
        case .pinging:
            return "Pinging"
        case .downloading:
            return "Download"
        case .uploading:
            return "Upload"
        default:
            return pingText
        }
    }

    private var remainingTimeText: String {
        "\(engine.estimatedRemainingSeconds)s"
    }

    private var hasDownloadValue: Bool {
        if isDownloadPhase {
            return engine.displayedGaugeSpeed > 0
        }
        return (engine.latestRecordedStats?.downloadMbps ?? 0) > 0
    }

    private var hasUploadValue: Bool {
        if isUploadPhase {
            return engine.displayedGaugeSpeed > 0
        }
        if isDownloadPhase {
            return (engine.latestRecordedStats?.uploadMbps ?? 0) > 0
        }
        return (engine.latestRecordedStats?.uploadMbps ?? 0) > 0
    }

    private var downloadNumericValue: Double {
        if isDownloadPhase {
            return engine.displayedGaugeSpeed
        }
        return engine.latestRecordedStats?.downloadMbps ?? 0.0
    }

    private var uploadNumericValue: Double {
        if isUploadPhase {
            return engine.displayedGaugeSpeed
        }
        return engine.latestRecordedStats?.uploadMbps ?? 0.0
    }

    private var pingNumericValue: Double {
        engine.latestRecordedStats?.pingMs ?? 0.0
    }

    private var downloadValueText: String {
        if isDownloadPhase {
            return engine.speedUnit.formatValueOnly(mbps: engine.displayedGaugeSpeed)
        }
        if let stats = engine.latestRecordedStats, stats.downloadMbps > 0 {
            return engine.speedUnit.formatValueOnly(mbps: stats.downloadMbps)
        }
        return "--"
    }

    private var uploadValueText: String {
        if isUploadPhase {
            return engine.speedUnit.formatValueOnly(mbps: engine.displayedGaugeSpeed)
        }
        if let stats = engine.latestRecordedStats, stats.uploadMbps > 0 {
            return engine.speedUnit.formatValueOnly(mbps: stats.uploadMbps)
        }
        return "--"
    }

    private var pingText: String {
        if let stats = engine.latestRecordedStats, stats.pingMs > 0 {
            return String(format: "%.0f ms", stats.pingMs)
        }
        return "-- ms"
    }
}
