import SwiftUI

struct ErrorLogsView: View {
    @StateObject private var service = ErrorLogsService()
    @State private var searchText = ""
    @State private var showGroqOnly = false
    @State private var selectedSeverity: String? = nil
    @State private var daysBack = 7

    private var filtered: [ErrorLogEntry] {
        var result = service.entries

        // Filter by search text
        if !searchText.isEmpty {
            result = result.filter {
                $0.message.localizedCaseInsensitiveContains(searchText) ||
                $0.resource.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Filter by severity
        if let severity = selectedSeverity {
            result = result.filter { $0.severity == severity }
        }

        // Filter for Groq errors
        if showGroqOnly {
            result = result.filter { $0.isGroqQuotaError }
        }

        return result
    }

    private var groqErrorCount: Int {
        service.entries.filter { $0.isGroqQuotaError }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if service.isLoading && !service.hasData {
                    loadingView
                } else if let err = service.error {
                    errorView(message: err)
                } else if service.entries.isEmpty && service.hasData {
                    ContentUnavailableView(
                        "No Errors Found",
                        systemImage: "checkmark.circle",
                        description: Text("No error logs in the last \(daysBack) days")
                    )
                } else {
                    contentView
                }
            }
            .navigationTitle("Error Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Picker("Time Range", selection: $daysBack) {
                            Text("Last 24 Hours").tag(1)
                            Text("Last 3 Days").tag(3)
                            Text("Last 7 Days").tag(7)
                            Text("Last 14 Days").tag(14)
                            Text("Last 30 Days").tag(30)
                        }
                    } label: {
                        Label("\(daysBack)d", systemImage: "calendar")
                    }

                    Button {
                        Task { await service.loadErrorLogs(daysBack: daysBack, groqOnly: false) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(service.isLoading)
                }
            }
            .task {
                await service.loadErrorLogs(daysBack: daysBack, groqOnly: false)
            }
            .onChange(of: daysBack) { _, _ in
                Task { await service.loadErrorLogs(daysBack: daysBack, groqOnly: false) }
            }
        }
    }

    // MARK: - Content View

    private var contentView: some View {
        VStack(spacing: 0) {
            // Summary card
            if groqErrorCount > 0 {
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Groq API Quota Errors")
                            .font(.subheadline.bold())
                        Spacer()
                        Text("\(groqErrorCount)")
                            .font(.title3.bold())
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal)
                    .padding(.top, 8)

                    Toggle("Show Groq Errors Only", isOn: $showGroqOnly)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }

            // Filter by severity
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(
                        title: "All",
                        count: service.entries.count,
                        isSelected: selectedSeverity == nil
                    ) {
                        selectedSeverity = nil
                    }

                    ForEach(uniqueSeverities, id: \.self) { severity in
                        let count = service.entries.filter { $0.severity == severity }.count
                        FilterChip(
                            title: severity,
                            count: count,
                            isSelected: selectedSeverity == severity,
                            color: severityColor(severity)
                        ) {
                            selectedSeverity = severity
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            // Error list
            List(filtered) { entry in
                ErrorLogRow(entry: entry)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search errors")
        }
    }

    private var uniqueSeverities: [String] {
        Array(Set(service.entries.map { $0.severity })).sorted()
    }

    // MARK: - Loading & Error Views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading error logs...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(message: String) -> some View {
        ContentUnavailableView(
            "Error Loading Logs",
            systemImage: "exclamationmark.triangle",
            description: Text(message)
        )
    }

    private func severityColor(_ severity: String) -> Color {
        switch severity {
        case "CRITICAL": return .red
        case "ERROR":    return .orange
        case "WARNING":  return .yellow
        default:         return .secondary
        }
    }
}

// MARK: - Error Log Row

struct ErrorLogRow: View {
    let entry: ErrorLogEntry

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                // Severity badge
                Text(entry.severity)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(severityColor.opacity(0.15))
                    .foregroundStyle(severityColor)
                    .clipShape(Capsule())

                // Groq badge if applicable
                if entry.isGroqQuotaError {
                    Text("GROQ")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15))
                        .foregroundStyle(.purple)
                        .clipShape(Capsule())
                }

                Spacer()

                // Timestamp
                Text(timeString(entry.timestamp))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            // Message
            Text(entry.message)
                .font(.caption.monospaced())
                .lineLimit(isExpanded ? nil : 3)
                .textSelection(.enabled)

            // Resource info (collapsible)
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    Text("Resource")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Text(entry.resource)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    if !entry.labels.isEmpty {
                        Text("Labels")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        ForEach(Array(entry.labels.keys.sorted()), id: \.self) { key in
                            Text("\(key): \(entry.labels[key] ?? "")")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }

            // Expand/Collapse button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(isExpanded ? "Show Less" : "Show More")
                        .font(.caption2)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    private var severityColor: Color {
        switch entry.severity {
        case "CRITICAL": return .red
        case "ERROR":    return .orange
        case "WARNING":  return .yellow
        default:         return .secondary
        }
    }

    private func timeString(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let df = DateFormatter()
            df.dateFormat = "MMM d, HH:mm"
            return df.string(from: date)
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let count: Int
    var isSelected: Bool
    var color: Color = .blue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                Text("(\(count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? color.opacity(0.15) : Color.gray.opacity(0.1))
            .foregroundStyle(isSelected ? color : .primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? color : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
