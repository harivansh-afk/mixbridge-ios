//
//  LogManager.swift
//  mixbridge
//
//  Centralized logging manager for in-app debug log viewing
//

import Foundation
import SwiftUI

// MARK: - Build Environment Detection

enum BuildEnvironment {
    case debug      // Running from Xcode
    case testFlight // TestFlight build
    case appStore   // App Store production build

    static var current: BuildEnvironment {
        #if DEBUG
        return .debug
        #else
        // Check for TestFlight by looking for sandbox receipt
        if let receiptURL = Bundle.main.appStoreReceiptURL {
            // TestFlight receipts contain "sandboxReceipt" in the path
            if receiptURL.lastPathComponent == "sandboxReceipt" {
                return .testFlight
            }
        }
        return .appStore
        #endif
    }

    /// Returns true if dev features should be enabled (Debug or TestFlight)
    static var isDevMode: Bool {
        current != .appStore
    }
}

// MARK: - Log Level

enum LogLevel: String, CaseIterable, Codable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"

    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "✅"
        case .warning: return "⚠️"
        case .error: return "❌"
        }
    }

    var color: Color {
        switch self {
        case .debug: return .gray
        case .info: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

// MARK: - Log Entry

struct LogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let message: String
    let file: String
    let function: String
    let line: Int

    init(
        level: LogLevel,
        message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.level = level
        self.message = message
        self.file = (file as NSString).lastPathComponent
        self.function = function
        self.line = line
    }

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }

    var shortDescription: String {
        "\(level.emoji) [\(formattedTimestamp)] \(message)"
    }

    var fullDescription: String {
        "\(level.emoji) [\(formattedTimestamp)] [\(level.rawValue)] \(file):\(line) \(function)\n\(message)"
    }
}

// MARK: - Log Manager

@Observable
final class LogManager {
    static let shared = LogManager()

    private(set) var logs: [LogEntry] = []
    private let maxLogs = 1000
    private let queue = DispatchQueue(label: "com.mixbridge.logmanager", qos: .utility)

    private init() {
        loadPersistedLogs()
    }

    // MARK: - Logging Methods

    func debug(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .debug, message: message, file: file, function: function, line: line)
    }

    func info(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .info, message: message, file: file, function: function, line: line)
    }

    func warning(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .warning, message: message, file: file, function: function, line: line)
    }

    func error(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .error, message: message, file: file, function: function, line: line)
    }

    // MARK: - Core Logging

    private func log(
        level: LogLevel,
        message: String,
        file: String,
        function: String,
        line: Int
    ) {
        let entry = LogEntry(
            level: level,
            message: message,
            file: file,
            function: function,
            line: line
        )

        queue.async { [weak self] in
            DispatchQueue.main.async {
                self?.addEntry(entry)
            }
        }

        // Also print to console in debug builds
        #if DEBUG
        print(entry.shortDescription)
        #endif
    }

    private func addEntry(_ entry: LogEntry) {
        logs.append(entry)

        // Trim old logs if exceeding max
        if logs.count > maxLogs {
            logs.removeFirst(logs.count - maxLogs)
        }

        // Persist logs
        persistLogs()
    }

    // MARK: - Log Management

    func clearLogs() {
        logs.removeAll()
        persistLogs()
    }

    func filteredLogs(level: LogLevel?) -> [LogEntry] {
        guard let level = level else { return logs }
        return logs.filter { $0.level == level }
    }

    func exportLogs() -> String {
        logs.map { $0.fullDescription }.joined(separator: "\n\n")
    }

    // MARK: - Persistence

    private var logsFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("debug_logs.json")
    }

    private func persistLogs() {
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let data = try JSONEncoder().encode(self.logs)
                try data.write(to: self.logsFileURL)
            } catch {
                // Silently fail persistence
            }
        }
    }

    private func loadPersistedLogs() {
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let data = try Data(contentsOf: self.logsFileURL)
                let loadedLogs = try JSONDecoder().decode([LogEntry].self, from: data)
                DispatchQueue.main.async {
                    self.logs = loadedLogs
                }
            } catch {
                // No persisted logs or failed to load
            }
        }
    }
}

// MARK: - Convenience Global Functions

/// These functions log in Debug and TestFlight builds, but are no-ops in App Store builds
func logDebug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    guard BuildEnvironment.isDevMode else { return }
    LogManager.shared.debug(message, file: file, function: function, line: line)
}

func logInfo(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    guard BuildEnvironment.isDevMode else { return }
    LogManager.shared.info(message, file: file, function: function, line: line)
}

func logWarning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    guard BuildEnvironment.isDevMode else { return }
    LogManager.shared.warning(message, file: file, function: function, line: line)
}

func logError(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    guard BuildEnvironment.isDevMode else { return }
    LogManager.shared.error(message, file: file, function: function, line: line)
}
