//
//  WarpSettingsPane.swift
//  Warp
//

import AppKit
@_weakLinked import DroppyKit
import SwiftUI

public struct WarpSettingsPane: View {
    @ObservedObject var engine: WarpEngine
    @State private var isShowingLogs = false
    @State private var isExporting = false

    @State private var isHistoryExpanded = false

    public init(engine: WarpEngine) {
        self.engine = engine
    }

    public var body: some View {
        DropletSettingsPane {
            preferencesSection
            serverSection
            historySection
            diagnosticsSection
            licensingSection
        }
    }

    private var serverSelectionBinding: Binding<String> {
        Binding(
            get: {
                switch engine.serverMode {
                case .automatic: return "auto"
                case .privateRelay: return "relay"
                case .bonjour(let name): return "bonjour:\(name)"
                case .customURL: return "custom"
                }
            },
            set: { newTag in
                if newTag == "auto" {
                    engine.serverMode = .automatic
                } else if newTag == "relay" {
                    engine.serverMode = .privateRelay
                } else if newTag == "custom" {
                    engine.serverMode = .customURL(url: engine.customServerURL)
                } else if newTag.hasPrefix("bonjour:") {
                    let name = String(newTag.dropFirst("bonjour:".count))
                    engine.serverMode = .bonjour(name: name)
                }
            }
        )
    }

    private var preferencesSection: some View {
        DropletSettingsSection {
            settingsSectionHeader("Preferences")
        } content: {
            DropletSettingsCard {
                DropletControlRow(
                    title: "Speed units",
                    icon: "speedometer",
                    infoTip: "Choose between Megabits per second (standard) or Megabytes per second."
                ) {
                    HStack {
                        Spacer(minLength: 0)
                        Picker("", selection: $engine.speedUnit) {
                            ForEach(SpeedUnit.allCases, id: \.self) { unit in
                                Text(unit.displayName).tag(unit)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }

                DropletControlRow(
                    title: "Test duration",
                    icon: "timer",
                    infoTip: "Choose the target speedtest duration. Longer tests provide higher accuracy for high-bandwidth connections."
                ) {
                    HStack {
                        Spacer(minLength: 0)
                        Picker("", selection: $engine.testDuration) {
                            ForEach(TestDuration.allCases, id: \.self) { duration in
                                Text(duration.displayName).tag(duration)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }

                DropletToggleRow(
                    title: "Show HUD notification",
                    icon: "bell.badge",
                    subtitle: "Display a compact speedtest result HUD on your screen when a test completes.",
                    isOn: $engine.showHUDOnFinish
                )

                DropletToggleRow(
                    title: "Retain last result on shelf",
                    icon: "clock.arrow.circlepath",
                    subtitle: "Keep the last test result with a Test Again button on the shelf instead of resetting to the GO screen when inactive.",
                    isOn: $engine.retainLastResult
                )
            }
        }
    }

    private var serverSection: some View {
        DropletSettingsSection {
            settingsSectionHeader("Server")
        } content: {
            DropletSettingsCard {
                DropletControlRow(
                    title: "Test server",
                    icon: "server.rack",
                    infoTip: "Select the endpoint to test against. Apple Edge automatically picks the closest edge CDN. You can also test via iCloud Private Relay, discovered local Bonjour servers, or a custom configuration URL."
                ) {
                    HStack {
                        Spacer(minLength: 0)
                        Picker("", selection: serverSelectionBinding) {
                            Text("Apple Edge (automatic)").tag("auto")
                            Text("iCloud Private Relay").tag("relay")
                            if !engine.discoveredBonjourServers.isEmpty {
                                Divider()
                                ForEach(engine.discoveredBonjourServers, id: \.self) { server in
                                    Text("Bonjour: \(server)").tag("bonjour:\(server)")
                                }
                            }
                            Divider()
                            Text("Custom configuration URL").tag("custom")
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }

                if case .customURL = engine.serverMode {
                    DropletControlRow(
                        title: "Custom URL",
                        icon: "link",
                        infoTip: "URL or local path with file:// scheme pointing to a networkQuality server configuration JSON."
                    ) {
                        TextField("Custom URL", text: $engine.customServerURL, prompt: Text("https://... or file://..."))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                    }
                }

                DropletControlRow(
                    title: "Local discovery",
                    icon: "bonjour",
                    infoTip: "Scan your local network for machines advertising networkQuality server instances via Bonjour."
                ) {
                    Button(engine.isScanningBonjour ? "Scanning…" : "Scan Bonjour") {
                        engine.discoverBonjourServers()
                    }
                    .buttonStyle(.bordered)
                    .disabled(engine.isScanningBonjour)
                }
            }
        }
    }

    private var historySection: some View {
        DropletSettingsSection {
            settingsSectionHeader("History")
        } content: {
            DropletSettingsCard {
                DropletControlRow(
                    title: "Recorded tests",
                    infoTip: "\(engine.history.count) tests stored locally in preferences."
                ) {
                    HStack(spacing: 12) {
                        if !engine.history.isEmpty {
                            Button("Clear history") {
                                engine.clearHistory()
                                isHistoryExpanded = false
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.secondary)
                        }

                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isHistoryExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(engine.history.isEmpty ? "None" : "\(engine.history.count) test\(engine.history.count == 1 ? "" : "s")")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                Image(systemName: isHistoryExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(engine.history.isEmpty)
                    }
                }

                if isHistoryExpanded && !engine.history.isEmpty {
                    ForEach(engine.history) { item in
                        DropletControlRow(
                            title: item.timestamp.formatted(.dateTime.day().month(.abbreviated).hour().minute())
                        ) {
                            HStack(spacing: 14) {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.green)
                                    Text(engine.speedUnit.format(mbps: item.downloadMbps))
                                        .font(.system(size: 13, weight: .semibold))
                                        .monospacedDigit()
                                }

                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.purple)
                                    Text(engine.speedUnit.format(mbps: item.uploadMbps))
                                        .font(.system(size: 13, weight: .semibold))
                                        .monospacedDigit()
                                }

                                Text(String(format: "%.0f ms", item.pingMs))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.yellow)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
    }

    private var diagnosticsSection: some View {
        DropletSettingsSection {
            settingsSectionHeader("Diagnostics and logs")
        } content: {
            DropletSettingsCard {
                DropletControlRow(
                    title: "Logs",
                    icon: "doc.text.magnifyingglass",
                    infoTip: "Attach these when reporting an issue. Warp keeps non-blocking rotating logs in ~/Library/Logs/Warp/."
                ) {
                    HStack(spacing: 8) {
                        Button(isExporting ? "Exporting…" : "Export…") {
                            exportLogs()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isExporting)

                        Button("Show in Finder") {
                            WarpLogExporter.showLogsInFinder()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var licensingSection: some View {
        DropletSettingsSection {
            settingsSectionHeader("Licensing and acknowledgements")
        } content: {
            DropletSettingsCard {
                DropletControlRow(
                    title: "Warp license",
                    icon: "checkmark.seal",
                    infoTip: "Warp is open-source software under the MIT License by Dinanath Dash."
                ) {
                    Text("MIT")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                DropletControlRow(
                    title: "Engine architecture",
                    icon: "apple.logo",
                    infoTip: "networkQuality is Apple's native network diagnostic tool built into macOS Monterey 12 and newer."
                ) {
                    Text("macOS built-in")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func exportLogs() {
        isExporting = true
        Task { @MainActor in
            do {
                let archiveURL = try await WarpLogExporter.exportLogs()

                let panel = NSSavePanel()
                panel.title = "Export logs"
                panel.nameFieldStringValue = archiveURL.lastPathComponent
                panel.allowedContentTypes = [.zip]
                panel.canCreateDirectories = true

                NSApp.activate(ignoringOtherApps: true)

                panel.begin { response in
                    defer {
                        try? FileManager.default.removeItem(at: archiveURL)
                        self.isExporting = false
                    }

                    guard response == .OK, let destinationURL = panel.url else { return }

                    do {
                        let fileManager = FileManager.default
                        if fileManager.fileExists(atPath: destinationURL.path) {
                            try fileManager.removeItem(at: destinationURL)
                        }
                        try fileManager.copyItem(at: archiveURL, to: destinationURL)
                    } catch {
                        WarpLog.error("Export logs failed: \(error.localizedDescription)")
                    }
                }
            } catch {
                isExporting = false
                WarpLog.error("Export logs failed: \(error.localizedDescription)")
            }
        }
    }
}
