//
//  DevLogsView.swift
//  mixbridge
//
//  Debug view for viewing in-app logs
//

import SwiftUI

struct DevLogsView: View {
    @State private var logManager = LogManager.shared
    @State private var minimumLevel: LogLevel = .info
    @State private var selectedCategory: LogCategory? = nil
    @State private var searchText = ""
    @State private var showingExportSheet = false
    @State private var showingClearConfirmation = false
    @State private var autoScroll = true

    private var filteredLogs: [LogEntry] {
        var logs = logManager.filteredLogs(minimumLevel: minimumLevel)

        if let selectedCategory {
            logs = logs.filter { $0.category == selectedCategory }
        }

        if !searchText.isEmpty {
            logs = logs.filter {
                $0.message.localizedCaseInsensitiveContains(searchText) ||
                $0.file.localizedCaseInsensitiveContains(searchText) ||
                $0.function.localizedCaseInsensitiveContains(searchText) ||
                $0.category.label.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Show latest logs first
        return logs.reversed()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            filterBar

            // Log list
            if filteredLogs.isEmpty {
                emptyState
            } else {
                logList
            }
        }
        .navigationTitle("Dev Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: { showingExportSheet = true }) {
                        Label("Export Logs", systemImage: "square.and.arrow.up")
                    }

                    Button(action: { autoScroll.toggle() }) {
                        Label(
                            autoScroll ? "Auto-scroll On" : "Auto-scroll Off",
                            systemImage: autoScroll ? "arrow.down.circle.fill" : "arrow.down.circle"
                        )
                    }

                    Divider()

                    Button(role: .destructive, action: { showingClearConfirmation = true }) {
                        Label("Clear Logs", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search logs...")
        .sheet(isPresented: $showingExportSheet) {
            ShareSheet(items: [logManager.exportLogs()])
        }
        .alert("Clear All Logs?", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                logManager.clearLogs()
            }
        } message: {
            Text("This will permanently delete all logs.")
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 0) {
            // Level filter (threshold)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(
                        title: "All",
                        isSelected: minimumLevel == .debug,
                        color: .blue
                    ) {
                        minimumLevel = .debug
                    }

                    FilterChip(
                        title: "✅ INFO+",
                        isSelected: minimumLevel == .info,
                        color: LogLevel.info.color
                    ) {
                        minimumLevel = .info
                    }

                    FilterChip(
                        title: "⚠️ WARNING+",
                        isSelected: minimumLevel == .warning,
                        color: LogLevel.warning.color
                    ) {
                        minimumLevel = .warning
                    }

                    FilterChip(
                        title: "❌ ERROR",
                        isSelected: minimumLevel == .error,
                        color: LogLevel.error.color
                    ) {
                        minimumLevel = .error
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            Divider()

            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(
                        title: "All Categories",
                        isSelected: selectedCategory == nil,
                        color: .blue
                    ) {
                        selectedCategory = nil
                    }

                    ForEach(LogCategory.allCases) { category in
                        FilterChip(
                            title: category.label,
                            isSelected: selectedCategory == category,
                            color: .secondary
                        ) {
                            selectedCategory = category
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
    }

    // MARK: - Log List

    private var logList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(filteredLogs) { entry in
                    LogEntryRow(entry: entry)
                        .id(entry.id)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
            }
            .listStyle(.plain)
            .onChange(of: filteredLogs.count) { _, _ in
                if autoScroll, let firstLog = filteredLogs.first {
                    withAnimation {
                        proxy.scrollTo(firstLog.id, anchor: .top)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Logs")
                .font(.headline)

            Text(selectedCategory != nil || !searchText.isEmpty || minimumLevel != .debug
                 ? "No logs match the current filters"
                 : "Logs will appear here as the app runs")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }
}

// MARK: - Log Entry Row

private struct LogEntryRow: View {
    let entry: LogEntry
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header row
            HStack(spacing: 6) {
                Text(entry.level.emoji)
                    .font(.caption)

                Text(entry.formattedTimestamp)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)

                Text(entry.level.rawValue)
                    .font(.caption.bold())
                    .foregroundColor(entry.level.color)

                Text(entry.category.label)
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)

                Spacer()

                Text(entry.file)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Message
            Text(entry.message)
                .font(.system(.footnote, design: .monospaced))
                .lineLimit(isExpanded ? nil : 3)
                .foregroundColor(.primary)

            // Expanded details
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Function: \(entry.function)")
                    Text("Line: \(entry.line)")
                }
                .font(.caption2.monospaced())
                .foregroundColor(.secondary)
                .padding(.top, 4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
        .contextMenu {
            Button(action: {
                UIPasteboard.general.string = entry.fullDescription
            }) {
                Label("Copy Log", systemImage: "doc.on.doc")
            }

            Button(action: {
                UIPasteboard.general.string = entry.message
            }) {
                Label("Copy Message", systemImage: "text.quote")
            }
        }
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? color.opacity(0.2) : Color(UIColor.tertiarySystemBackground))
                .foregroundColor(isSelected ? color : .secondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? color : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        DevLogsView()
    }
    .onAppear {
        // Add sample logs for preview
        LogManager.shared.info("App launched", category: .app)
        LogManager.shared.info("User authenticated successfully")
        LogManager.shared.warning("Network request took longer than expected")
        LogManager.shared.error("Failed to load artwork: URL was nil")
        LogManager.shared.info("Playing track: Some Artist - Some Track", category: .playback)
        LogManager.shared.info("Cache hit for stream URL", category: .cache)
    }
}
#endif
