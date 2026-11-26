//
//  WarpHarness.swift
//  Warp
//
//  Run with: droppykit run
//

import DroppyKit
import DroppyKitHarness
import Warp

@main
struct WarpHarness: DropletHarnessApp {
    static func makeDroplet() -> any Droplet { WarpDroplet() }
}
