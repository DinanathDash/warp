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
    public static let preferredSoloWidth: CGFloat = 380
    public static let preferredPairedWidth: CGFloat = 190
    public static let minimumWidth: CGFloat = 140
    public static let pairWeight: Double = 0.62

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

    private var dialSize: CGFloat {
        if context.isCompact {
            return 90
        }
        return 114
    }

    public var body: some View {
        VStack(spacing: 0) {
            if !context.isCompact {
                headerRow
            }

            if context.isCompact {
                compactLayout
            } else {
                spaciousLayout
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

    // MARK: - Header (Settings & Expand above notch line)

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
        .accessibilityLabel("Warp settings")
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
        .help("Open expanded view")
        .accessibilityLabel("Open expanded view")
    }

    // MARK: - Spacious Layout

    private var spaciousLayout: some View {
        HStack(alignment: .center, spacing: DroppySpacing.xl) {
            gaugeButton(size: dialSize)

            VStack(alignment: .center, spacing: 10) {
                // Row 1: Designated Download & Upload telemetry areas (50/50)
                telemetryColumns(isSpacious: true)

                // Row 2: Ping / Live testing state in the center in a single line
                pingStatusRow(isSpacious: true)

                // Row 3: Action buttons (Copy + compact Start/Cancel)
                actionButtonsRow(isSpacious: true)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Compact Layout

    private var compactLayout: some View {
        HStack(alignment: .center, spacing: DroppySpacing.sm) {
            gaugeButton(size: dialSize)

            VStack(alignment: .center, spacing: 6) {
                HStack {
                    Spacer(minLength: 0)
                    expandButton
                }
                .padding(.top, -2)

                telemetryColumns(isSpacious: false)
                pingStatusRow(isSpacious: false)
                actionButtonsRow(isSpacious: false)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func gaugeButton(size: CGFloat) -> some View {
        Button(action: onOpenExpanded) {
            WarpGaugeView(
                speedMbps: currentDisplaySpeed,
                phase: gaugePhase,
                unit: engine.speedUnit,
                size: size,
                showTicks: false,
                progress: engine.testProgress,
                interfaceIcon: engine.activeInterfaceIcon,
                usesAdaptiveForegrounds: context.usesAdaptiveForegrounds
            )
        }
        .buttonStyle(.plain)
        .help("Open expanded speedtest")
        .accessibilityLabel("Open expanded speedtest")
    }

    // MARK: - Telemetry Columns (Download & Upload in half width)

    private func telemetryColumns(isSpacious: Bool) -> some View {
        HStack(spacing: 0) {
            // Download column
            VStack(alignment: .center, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: isSpacious ? 11 : 9, weight: .bold))
                        .foregroundStyle(.green)

                    Text(downloadValueText)
                        .font(.system(size: isSpacious ? 20 : 15, weight: .bold))
                        .foregroundStyle(hasDownloadValue ? .green : primaryInk)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: downloadNumericValue))
                        .animation(.smooth(duration: 0.3), value: downloadValueText)
                        .lineLimit(1)
                }

                Text(hasDownloadValue ? engine.speedUnit.rawValue : "Download")
                    .font(.system(size: isSpacious ? 11 : 9, weight: .medium))
                    .foregroundStyle(hasDownloadValue ? Color.green.opacity(0.85) : secondaryInk)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            // Upload column
            VStack(alignment: .center, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: isSpacious ? 11 : 9, weight: .bold))
                        .foregroundStyle(.purple)

                    Text(uploadValueText)
                        .font(.system(size: isSpacious ? 20 : 15, weight: .bold))
                        .foregroundStyle(hasUploadValue ? .purple : primaryInk)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: uploadNumericValue))
                        .animation(.smooth(duration: 0.3), value: uploadValueText)
                        .lineLimit(1)
                }

                Text(hasUploadValue ? engine.speedUnit.rawValue : "Upload")
                    .font(.system(size: isSpacious ? 11 : 9, weight: .medium))
                    .foregroundStyle(hasUploadValue ? Color.purple.opacity(0.85) : secondaryInk)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Ping / Live Status Row (Single line, centered)

    private func pingStatusRow(isSpacious: Bool) -> some View {
        HStack(spacing: 5) {
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
                    .font(.system(size: isSpacious ? 11 : 9, weight: .medium))
                    .foregroundStyle(secondaryInk)
                Text(pingText)
                    .font(.system(size: isSpacious ? 12 : 10, weight: .medium))
                    .foregroundStyle(secondaryInk)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: pingNumericValue))
                    .animation(.smooth(duration: 0.3), value: pingText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Action Buttons Row (Copy + reduced-width Cyan/Blue button)

    private func actionButtonsRow(isSpacious: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                copyLatestStats()
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: isSpacious ? 13 : 11, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(
                DroppyWashCircleButtonStyle(
                    diameter: isSpacious ? 28 : 24,
                    tone: didCopy ? .accent(.cyan) : .neutral,
                    glyphSize: isSpacious ? 13 : 11,
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
                        .font(.system(size: 10, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                    Text(isTesting ? "Cancel" : (engine.latestRecordedStats == nil ? "Start" : "Test Again"))
                        .font(.system(size: isSpacious ? 12.5 : 11, weight: .semibold))
                }
                .padding(.horizontal, isSpacious ? 14 : 10)
            }
            .buttonStyle(
                DroppyWashPillButtonStyle(
                    height: isSpacious ? 28 : 24,
                    tone: isTesting ? .neutral : .accent(.cyan),
                    fillsWidth: false,
                    usesAdaptiveForegrounds: context.usesAdaptiveForegrounds
                )
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
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
