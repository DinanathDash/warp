//
//  WarpHUD.swift
//  Warp
//

import AppKit
@_weakLinked import DroppyKit
import SwiftUI

@MainActor
enum WarpHUD {
    static let resultHUDID = "warp.result"

    static func presentResult(telemetry: SpeedtestTelemetry, unit: SpeedUnit, host: DropletHost?) {
        guard let host, host.isGranted(.hud) else { return }

        let dlStr = unit.format(mbps: telemetry.downloadMbps)
        let ulStr = unit.format(mbps: telemetry.uploadMbps)
        let pingStr = String(format: "%.0f ms", telemetry.pingMs)

        let card = DropletHUDCard(
            title: "Speedtest Complete",
            message: "Download: \(dlStr) · Upload: \(ulStr) · Ping: \(pingStr)",
            systemImage: "gauge.with.needle.fill",
            tint: Color(white: 0.82),
            progress: nil,
            actions: [
                DropletHUDAction(id: "open_surface", title: "View Details", isPrimary: true) {
                    let req = ExpandedSurfacePresentationRequest(surfaceID: WarpDroplet.expandedSurfaceID, opensShelf: true)
                    _ = host.notchSurface.presentExpandedSurface(req)
                }
            ]
        )

        let request = DropletHUDRequest(
            id: resultHUDID,
            duration: 4.5,
            priority: .normal,
            accessibilityLabel: "Speedtest Complete: \(dlStr) download, \(ulStr) upload",
            card: card,
            isExpanded: true
        ) {
            Image(systemName: "gauge.with.needle.fill")
                .font(.system(size: DroppyLiveActivityMetrics.iconSize, weight: .semibold))
                .foregroundStyle(Color(white: 0.82))
        } trailing: {
            HStack(spacing: 4) {
                Text(dlStr)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }

        _ = host.hud.present(request)
    }
}
