//
//  LogManager.swift
//  mixbridge
//
//  Centralized logging manager for in-app debug log viewing
//

import Foundation
import OSLog
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

enum LogLevel: String, CaseIterable, Codable, Comparable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"

    private var sortOrder: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }

    init?(environmentValue: String) {
        switch environmentValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "debug": self = .debug
        case "info": self = .info
        case "warning", "warn": self = .warning
        case "error": self = .error
        default: return nil
        }
    }

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

// MARK: - Log Category

enum LogCategory: String, CaseIterable, Codable, Identifiable {
    case app
    case auth
    case network
    case playback
    case cache
    case preload
    case ui
    case rendering
    case queue
    case db
    case sync
    case downloads
    case dj

    var id: String { rawValue }

    var label: String {
        switch self {
        case .app: return "App"
        case .auth: return "Auth"
        case .network: return "Network"
        case .playback: return "Playback"
        case .cache: return "Cache"
        case .preload: return "Preload"
        case .ui: return "UI"
        case .rendering: return "Rendering"
        case .queue: return "Queue"
        case .db: return "Database"
        case .sync: return "Sync"
        case .downloads: return "Downloads"
        case .dj: return "DJ"
        }
    }
}

// MARK: - Log Entry

struct LogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let category: LogCategory
    let message: String
    let file: String
    let function: String
    let line: Int

    init(
        level: LogLevel,
        category: LogCategory = .app,
        message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.level = level
        self.category = category
        self.message = message
        self.file = (file as NSString).lastPathComponent
        self.function = function
        self.line = line
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case level
        case category
        case message
        case file
        case function
        case line
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        level = try container.decode(LogLevel.self, forKey: .level)
        category = (try? container.decode(LogCategory.self, forKey: .category)) ?? .app
        message = try container.decode(String.self, forKey: .message)
        file = try container.decode(String.self, forKey: .file)
        function = try container.decode(String.self, forKey: .function)
        line = try container.decode(Int.self, forKey: .line)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(level, forKey: .level)
        try container.encode(category, forKey: .category)
        try container.encode(message, forKey: .message)
        try container.encode(file, forKey: .file)
        try container.encode(function, forKey: .function)
        try container.encode(line, forKey: .line)
    }

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }

    var shortDescription: String {
        "\(level.emoji) [\(formattedTimestamp)] [\(category.label)] \(message)"
    }

    var fullDescription: String {
        "\(level.emoji) [\(formattedTimestamp)] [\(level.rawValue)] [\(category.label)] \(file):\(line) \(function)\n\(message)"
    }
}

// MARK: - Log Manager

@Observable
final class LogManager {
    static let shared = LogManager()

    private(set) var logs: [LogEntry] = []
    private let maxLogs = 1000
    private let queue = DispatchQueue(label: "com.mixbridge.logmanager", qos: .utility)
    private var persistWorkItem: DispatchWorkItem?

    private enum EnvironmentKey {
        static let consoleLogLevel = "MIXBRIDGE_CONSOLE_LOG_LEVEL"
        static let inAppLogLevel = "MIXBRIDGE_IN_APP_LOG_LEVEL"
        static let disablePersistedLogs = "MIXBRIDGE_DISABLE_PERSISTED_LOGS"
    }

    private init() {
        loadPersistedLogs()
    }

    // MARK: - Logging Methods

    func debug(
        _ message: @autoclosure () -> String,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .debug, category: category, message: message, file: file, function: function, line: line)
    }

    func info(
        _ message: @autoclosure () -> String,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .info, category: category, message: message, file: file, function: function, line: line)
    }

    func warning(
        _ message: @autoclosure () -> String,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .warning, category: category, message: message, file: file, function: function, line: line)
    }

    func error(
        _ message: @autoclosure () -> String,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .error, category: category, message: message, file: file, function: function, line: line)
    }

    // MARK: - Core Logging

    private func log(
        level: LogLevel,
        category: LogCategory,
        message: String,
        file: String,
        function: String,
        line: Int
    ) {
        log(
            level: level,
            category: category,
            message: { message },
            file: file,
            function: function,
            line: line
        )
    }

    func debug(
        message: () -> String,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .debug, category: category, message: message, file: file, function: function, line: line)
    }

    func info(
        message: () -> String,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .info, category: category, message: message, file: file, function: function, line: line)
    }

    func warning(
        message: () -> String,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .warning, category: category, message: message, file: file, function: function, line: line)
    }

    func error(
        message: () -> String,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .error, category: category, message: message, file: file, function: function, line: line)
    }

    private func log(
        level: LogLevel,
        category: LogCategory,
        message: () -> String,
        file: String,
        function: String,
        line: Int
    ) {
        let shouldCaptureInApp = BuildEnvironment.isDevMode && level >= inAppMinimumLevel
        let shouldEmitConsole = shouldLogToConsole(level: level)

        guard shouldCaptureInApp || shouldEmitConsole else { return }

        let renderedMessage = message()

        let entry = LogEntry(
            level: level,
            category: category,
            message: renderedMessage,
            file: file,
            function: function,
            line: line
        )

        if shouldCaptureInApp {
            queue.async { [weak self] in
                DispatchQueue.main.async {
                    self?.addEntry(entry)
                }
            }
        }

        if shouldEmitConsole {
            emitToConsole(entry)
        }
    }

    private var consoleMinimumLevel: LogLevel {
        if let env = ProcessInfo.processInfo.environment[EnvironmentKey.consoleLogLevel],
           let parsed = LogLevel(environmentValue: env) {
            return parsed
        }
        // Default: keep Xcode console readable.
        return .warning
    }

    private var inAppMinimumLevel: LogLevel {
        if let env = ProcessInfo.processInfo.environment[EnvironmentKey.inAppLogLevel],
           let parsed = LogLevel(environmentValue: env) {
            return parsed
        }
        // Default: avoid drowning the in-app log view.
        return .info
    }

    private var persistedLogsEnabled: Bool {
        guard BuildEnvironment.isDevMode else { return false }
        if let env = ProcessInfo.processInfo.environment[EnvironmentKey.disablePersistedLogs] {
            return env == "0" || env.lowercased() == "false" ? true : false
        }
        return true
    }

    private func shouldLogToConsole(level: LogLevel) -> Bool {
        if BuildEnvironment.isDevMode {
            return level >= consoleMinimumLevel
        }
        // In production, keep only actionable logs in unified logging.
        return level >= .warning
    }

    private func emitToConsole(_ entry: LogEntry) {
        let subsystem = Bundle.main.bundleIdentifier ?? "mixbridge"
        let logger = Logger(subsystem: subsystem, category: entry.category.label)
        let message = "[\(entry.level.rawValue)] \(entry.file):\(entry.line) \(entry.function) — \(entry.message)"
        if BuildEnvironment.isDevMode {
            logger.log(level: entry.level.osLogType, "\(message, privacy: .public)")
        } else {
            logger.log(level: entry.level.osLogType, "\(message, privacy: .private(mask: .hash))")
        }
    }

    private func addEntry(_ entry: LogEntry) {
        logs.append(entry)

        // Trim old logs if exceeding max
        if logs.count > maxLogs {
            logs.removeFirst(logs.count - maxLogs)
        }

        // Persist logs (debounced)
        schedulePersistLogs()
    }

    // MARK: - Log Management

    func clearLogs() {
        logs.removeAll()
        schedulePersistLogs(immediate: true)
    }

    func filteredLogs(minimumLevel: LogLevel = .debug) -> [LogEntry] {
        logs.filter { $0.level >= minimumLevel }
    }

    func exportLogs() -> String {
        logs.map { $0.fullDescription }.joined(separator: "\n\n")
    }

    // MARK: - Persistence

    private var logsFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("debug_logs.json")
    }

    private func loadPersistedLogs() {
        guard persistedLogsEnabled else { return }
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

    private func schedulePersistLogs(immediate: Bool = false) {
        guard persistedLogsEnabled else { return }
        persistWorkItem?.cancel()

        let snapshot = logs
        let url = logsFileURL
        let delay: DispatchTimeInterval = immediate ? .milliseconds(0) : .milliseconds(750)
        let workItem = DispatchWorkItem {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url)
            } catch {
                // Silently fail persistence
            }
        }
        persistWorkItem = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}

// MARK: - Convenience Global Functions

/// These functions log in Debug and TestFlight builds, but are no-ops in App Store builds
func logDebug(_ message: @autoclosure () -> String, file: String = #file, function: String = #function, line: Int = #line) {
    guard BuildEnvironment.isDevMode else { return }
    LogManager.shared.debug(message: message, file: file, function: function, line: line)
}

func logInfo(_ message: @autoclosure () -> String, file: String = #file, function: String = #function, line: Int = #line) {
    guard BuildEnvironment.isDevMode else { return }
    LogManager.shared.info(message: message, file: file, function: function, line: line)
}

func logWarning(_ message: @autoclosure () -> String, file: String = #file, function: String = #function, line: Int = #line) {
    guard BuildEnvironment.isDevMode else { return }
    LogManager.shared.warning(message: message, file: file, function: function, line: line)
}

func logError(_ message: @autoclosure () -> String, file: String = #file, function: String = #function, line: Int = #line) {
    guard BuildEnvironment.isDevMode else { return }
    LogManager.shared.error(message: message, file: file, function: function, line: line)
}

/// Category-aware variants (recommended)
func logDebug(_ category: LogCategory, _ message: @autoclosure () -> String, file: String = #file, function: String = #function, line: Int = #line) {
    guard BuildEnvironment.isDevMode else { return }
    LogManager.shared.debug(message: message, category: category, file: file, function: function, line: line)
}

func logInfo(_ category: LogCategory, _ message: @autoclosure () -> String, file: String = #file, function: String = #function, line: Int = #line) {
    guard BuildEnvironment.isDevMode else { return }
    LogManager.shared.info(message: message, category: category, file: file, function: function, line: line)
}

func logWarning(_ category: LogCategory, _ message: @autoclosure () -> String, file: String = #file, function: String = #function, line: Int = #line) {
    guard BuildEnvironment.isDevMode else { return }
    LogManager.shared.warning(message: message, category: category, file: file, function: function, line: line)
}

func logError(_ category: LogCategory, _ message: @autoclosure () -> String, file: String = #file, function: String = #function, line: Int = #line) {
    guard BuildEnvironment.isDevMode else { return }
    LogManager.shared.error(message: message, category: category, file: file, function: function, line: line)
}
