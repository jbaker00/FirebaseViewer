import SwiftUI

struct LogView: View {
    @ObservedObject private var logger = AppLogger.shared
    @State private var searchText = ""
    @State private var showingShareSheet = false

    private var filtered: [AppLogger.Entry] {
        guard !searchText.isEmpty else { return logger.entries.reversed() }
        return logger.entries.reversed().filter {
            $0.message.localizedCaseInsensitiveContains(searchText) ||
            $0.tag.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if logger.entries.isEmpty {
                    ContentUnavailableView("No Logs Yet",
                                          systemImage: "scroll",
                                          description: Text("Logs appear here as the app makes API calls."))
                } else {
                    List(filtered) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(entry.tag)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(tagColor(entry.tag).opacity(0.15))
                                    .foregroundStyle(tagColor(entry.tag))
                                    .clipShape(Capsule())
                                Spacer()
                                Text(timeString(entry.timestamp))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                            Text(entry.message)
                                .font(.caption.monospaced())
                                .foregroundStyle(entry.message.hasPrefix("⚠️") ? .red : .primary)
                                .textSelection(.enabled)
                        }
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .searchable(text: $searchText, prompt: "Filter logs")
                }
            }
            .navigationTitle("Debug Logs")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(logger.entries.isEmpty)

                    Button(role: .destructive) {
                        logger.clearLogs()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(logger.entries.isEmpty)
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: [allLogsText()])
            }
        }
    }

    // MARK: - Helpers

    private func timeString(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df.string(from: date)
    }

    private func tagColor(_ tag: String) -> Color {
        switch tag {
        case "Error":     return .red
        case "AdMob":     return .orange
        case "GA4":       return .blue
        case "Firestore": return .green
        default:          return .secondary
        }
    }

    private func allLogsText() -> String {
        logger.entries.map { $0.formatted }.joined(separator: "\n")
    }
}

// MARK: - UIActivityViewController wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}
