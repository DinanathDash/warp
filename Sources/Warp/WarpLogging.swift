//
//  WarpLogging.swift
//  Warp
//

import AppKit
import Foundation
import os
import UniformTypeIdentifiers
@_weakLinked import DroppyKit

public final class WarpRotatingFileLogSink: @unchecked Sendable {
    public static let shared = WarpRotatingFileLogSink()

    public static var defaultLogDirectory: URL {
        let libraryLogs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        return libraryLogs.appendingPathComponent("Logs/Warp")
    }

    private let logDirectory: URL
    private let fileName: String = "warp.log"
    private let maxFileSize: UInt64 = 5 * 1024 * 1024 // 5 MB
    private let maxBackups: Int = 3
    private let maxLogAgeDays: TimeInterval = 7 // Auto-purge logs older than 7 days

    private let queue = DispatchQueue(
        label: "app.getdroppy.droplet.warp.log",
        qos: .utility
    )
    private var fileHandle: FileHandle?
    private var currentFileSize: UInt64 = 0

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    public init(logDirectory: URL? = nil) {
        self.logDirectory = logDirectory ?? Self.defaultLogDirectory
        queue.sync {
            self.prepareLogFile()
            self.purgeOlderLogs()
        }
    }

    public static func setup() {
        _ = shared
    }

    private func prepareLogFile() {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: logDirectory.path) {
            try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        }
        let url = currentFileURL
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: url)
        if let handle = fileHandle {
            currentFileSize = (try? handle.seekToEnd()) ?? 0
        }
    }

    /// Auto-purge log files older than `maxLogAgeDays` or beyond `maxBackups`
    public func purgeOlderLogs() {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: logDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoffDate = Date().addingTimeInterval(-(maxLogAgeDays * 86400))

        for file in files {
            let name = file.lastPathComponent
            guard name.hasPrefix("warp") && name.hasSuffix(".log") else { continue }
            if name == fileName { continue }

            if let attributes = try? fileManager.attributesOfItem(atPath: file.path),
               let modDate = attributes[.modificationDate] as? Date,
               modDate < cutoffDate {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    public func record(date: Date = Date(), level: String, message: String) {
        queue.async { [weak self] in
            guard let self else { return }
            let formattedDate = self.dateFormatter.string(from: date)
            let line = "\(formattedDate) [\(level)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            self.write(data)
        }
    }

    public func flush() {
        queue.sync {
            try? fileHandle?.synchronize()
        }
    }

    private var currentFileURL: URL {
        logDirectory.appendingPathComponent(fileName)
    }

    private func backupFileURL(index: Int) -> URL {
        logDirectory.appendingPathComponent("warp.\(index).log")
    }

    private func write(_ data: Data) {
        if fileHandle == nil {
            prepareLogFile()
        }
        guard let fileHandle else { return }
        if currentFileSize + UInt64(data.count) > maxFileSize {
            rotate()
        }
        try? fileHandle.write(contentsOf: data)
        currentFileSize += UInt64(data.count)
    }

    private func rotate() {
        try? fileHandle?.synchronize()
        try? fileHandle?.close()
        fileHandle = nil

        let fileManager = FileManager.default
        let oldestBackup = backupFileURL(index: maxBackups)
        if fileManager.fileExists(atPath: oldestBackup.path) {
            try? fileManager.removeItem(at: oldestBackup)
        }

        for i in stride(from: maxBackups - 1, through: 1, by: -1) {
            let source = backupFileURL(index: i)
            let dest = backupFileURL(index: i + 1)
            if fileManager.fileExists(atPath: source.path) {
                try? fileManager.moveItem(at: source, to: dest)
            }
        }

        let firstBackup = backupFileURL(index: 1)
        if fileManager.fileExists(atPath: currentFileURL.path) {
            try? fileManager.moveItem(at: currentFileURL, to: firstBackup)
        }

        purgeOlderLogs()
        prepareLogFile()
    }
}

public enum WarpLog {
    private static let logger = Logger(subsystem: "app.getdroppy.droplet.warp", category: "Engine")

    public static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        WarpRotatingFileLogSink.shared.record(level: "DEBUG", message: message)
    }

    public static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        WarpRotatingFileLogSink.shared.record(level: "INFO", message: message)
    }

    public static func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        WarpRotatingFileLogSink.shared.record(level: "NOTICE", message: message)
    }

    public static func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
        WarpRotatingFileLogSink.shared.record(level: "WARNING", message: message)
    }

    public static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        WarpRotatingFileLogSink.shared.record(level: "ERROR", message: message)
    }
}

@MainActor
public enum WarpLogExporter {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    public static func exportLogs(
        from directory: URL = WarpRotatingFileLogSink.defaultLogDirectory,
        date: Date = Date()
    ) async throws -> URL {
        WarpRotatingFileLogSink.shared.flush()

        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let mainLogURL = directory.appendingPathComponent("warp.log")
        if !fileManager.fileExists(atPath: mainLogURL.path) {
            if directory == WarpRotatingFileLogSink.defaultLogDirectory {
                WarpLog.info("Log session initialized for export")
                WarpRotatingFileLogSink.shared.flush()
            }
            if !fileManager.fileExists(atPath: mainLogURL.path) {
                fileManager.createFile(atPath: mainLogURL.path, contents: "Warp log session initialized\n".data(using: .utf8))
            }
        }

        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let logFiles = contents.filter { url in
            let name = url.lastPathComponent
            return name.hasPrefix("warp") && name.hasSuffix(".log")
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !logFiles.isEmpty else {
            throw NSError(domain: "WarpLogExporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "No log files found to export."])
        }

        let dateString = dateFormatter.string(from: date)
        let archiveURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Warp-Logs-\(dateString).zip")
        if fileManager.fileExists(atPath: archiveURL.path) {
            try? fileManager.removeItem(at: archiveURL)
        }

        try await Task.detached(priority: .utility) {
            var coordinationError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: directory, options: .forUploading, error: &coordinationError) { zipURL in
                do {
                    try FileManager.default.copyItem(at: zipURL, to: archiveURL)
                } catch {
                    copyError = error
                }
            }
            if let error = coordinationError ?? copyError { throw error }
        }.value

        guard fileManager.fileExists(atPath: archiveURL.path) else {
            throw NSError(domain: "WarpLogExporter", code: 2, userInfo: [NSLocalizedDescriptionKey: "The log archive was not created."])
        }
        return archiveURL
    }

    public static func showLogsInFinder(directory: URL = WarpRotatingFileLogSink.defaultLogDirectory) {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            WarpLog.info("Created logs directory")
            WarpRotatingFileLogSink.shared.flush()
        }
        let currentLog = directory.appendingPathComponent("warp.log")
        if !fileManager.fileExists(atPath: currentLog.path) {
            fileManager.createFile(atPath: currentLog.path, contents: nil)
        }
        if fileManager.fileExists(atPath: currentLog.path) {
            NSWorkspace.shared.activateFileViewerSelecting([currentLog])
        } else {
            NSWorkspace.shared.open(directory)
        }
    }
}
