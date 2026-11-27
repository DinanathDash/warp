//
//  WarpDroplet.swift
//  Warp
//

import AppKit
import Combine
@_weakLinked import DroppyKit
import SwiftUI

/// The class Droppy's loader instantiates, named in the bundle's
/// `NSPrincipalClass`. Keep it empty: it runs before the host is ready.
@objc(WarpPrincipal)
public final class WarpPrincipal: NSObject, DropletPrincipal {
    public override init() { super.init() }

    @MainActor public func makeDroplet() -> AnyObject { WarpDroplet() }
}

public final class WarpDroplet: NSObject, ObservableObject, Droplet {
    public nonisolated static let id: DropletID = "warp"
    public static let widgetID: ShelfWidgetID = "warp.main"
    public static let expandedSurfaceID: ExpandedSurfaceID = "warp.detail"

    public let engine = WarpEngine()
    public private(set) var host: DropletHost?

    private var engineCancellable: AnyCancellable?
    private var layoutCancellable: AnyCancellable?
    private var expandedSurfacePresentation: ExpandedSurfacePresentation?
    private var lastObservedPhase: SpeedtestPhase = .idle

    public override init() {
        super.init()

        engineCancellable = engine.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            self.objectWillChange.send()
            self.handleEngineChange()
        }

        // Emit after @Published telemetry/phase mutations commit so the host
        // reads fresh expandedSurfaceSize values when bento rows enter or leave.
        layoutCancellable = Publishers.CombineLatest(engine.$currentTelemetry, engine.$phase)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.objectWillChange.send()
            }
    }

    public func activate(host: DropletHost) throws {
        self.host = host
        WarpRotatingFileLogSink.setup()
        WarpLog.info("Warp activated")
        host.log.info("Warp activated")

        engine.attach(preferences: host.preferences)
        engine.onHistoryCleared = { [weak self] in
            guard let self else { return }
            self.host?.hud.dismiss(id: WarpHUD.resultHUDID)
        }
    }

    public func deactivate() {
        WarpLog.info("Warp deactivating")
        host?.log.info("Warp deactivating")
        dismissExpandedSurface()
        engine.stop()
        engine.detachPreferences()
        WarpRotatingFileLogSink.shared.flush()
        host = nil
    }

    public func openSettings() {
        _ = host?.workspace.openSettings()
    }

    public func presentExpandedSurface() {
        guard let host else { return }
        let request = ExpandedSurfacePresentationRequest(surfaceID: Self.expandedSurfaceID, opensShelf: true)
        expandedSurfacePresentation = host.notchSurface.presentExpandedSurface(request)
    }

    public func dismissExpandedSurface() {
        host?.notchSurface.dismissExpandedSurface(Self.expandedSurfaceID)
        expandedSurfacePresentation = nil
    }

    public func collapseToHUD() {
        dismissExpandedSurface()
        if let telemetry = engine.currentTelemetry, engine.showHUDOnFinish {
            WarpHUD.presentResult(telemetry: telemetry, unit: engine.speedUnit, host: host)
        } else {
            _ = host?.shelf.open(revealing: Self.widgetID)
        }
    }

    private func handleEngineChange() {
        let currentPhase = engine.phase
        if lastObservedPhase.isTesting && currentPhase == .completed, let telemetry = engine.currentTelemetry {
            if engine.showHUDOnFinish {
                WarpHUD.presentResult(telemetry: telemetry, unit: engine.speedUnit, host: host)
            }
        }
        lastObservedPhase = currentPhase
    }
}

extension WarpDroplet: ShelfWidgetProviding {
    public var widgetDescriptors: [ShelfWidgetDescriptor] {
        [
            ShelfWidgetDescriptor(
                id: Self.widgetID,
                title: "Warp",
                systemImage: "speedometer",
                layoutTraits: ShelfWidgetLayoutTraits(
                    preferredSoloWidth: WarpShelfWidgetView.preferredSoloWidth,
                    preferredPairedWidth: WarpShelfWidgetView.preferredPairedWidth,
                    contentHeight: .fixed(WarpShelfWidgetView.contentHeight),
                    notchWrap: ShelfWidgetNotchWrapTraits(headerHeight: 28, besideExtent: 56)
                ),
                searchKeywords: ["speedtest", "speed", "bandwidth", "network", "ping", "gauge"]
            )
        ]
    }

    public func makeWidgetView(_ id: ShelfWidgetID, context: ShelfWidgetContext) -> AnyView {
        AnyView(WarpShelfWidgetView(
            engine: engine,
            context: context,
            onOpenExpanded: { [weak self] in
                self?.presentExpandedSurface()
            },
            onOpenSettings: { [weak self] in
                self?.openSettings()
            }
        ))
    }

    public func makeWidgetSettingsPopover(_ id: ShelfWidgetID) -> AnyView? { nil }
}

extension WarpDroplet: SettingsPaneProviding {
    public func makeSettingsPane(context: SettingsPaneContext) -> AnyView {
        AnyView(WarpSettingsPane(engine: engine))
    }
}

extension WarpDroplet: HUDPresenting {}

extension WarpDroplet: ExpandedSurfaceHosting, ExpandedSurfaceProviding {
    public var expandedSurfaceProvider: (any ExpandedSurfaceProviding)? { self }

    public var expandedSurfaces: [ExpandedSurfaceDescriptor] {
        [
            ExpandedSurfaceDescriptor(
                id: Self.expandedSurfaceID,
                title: "Speedtest",
                systemImage: "speedometer",
                suppresses: [.shelfWidgets, .autoCollapse]
            )
        ]
    }

    public func makeExpandedSurfaceView(_ id: ExpandedSurfaceID, context: ExpandedSurfaceContext) -> AnyView {
        AnyView(WarpExpandedSurfaceView(
            engine: engine,
            onDismiss: { [weak self] in
                self?.dismissExpandedSurface()
            },
            onCollapse: { [weak self] in
                self?.collapseToHUD()
            },
            onOpenSettings: { [weak self] in
                self?.openSettings()
            }
        ))
    }

    public func expandedSurfaceSize(
        _ id: ExpandedSurfaceID,
        fitting proposal: ExpandedSurfaceSizeProposal
    ) -> CGSize? {
        CGSize(width: 520, height: 268)
    }

    public func expandedSurfaceDidDismiss(
        _ id: ExpandedSurfaceID,
        presentation: ExpandedSurfacePresentation,
        reason: ExpandedSurfaceDismissalReason
    ) {
        if expandedSurfacePresentation?.id == presentation.id {
            expandedSurfacePresentation = nil
        }
    }
}
