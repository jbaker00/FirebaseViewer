import SwiftUI

struct AppVersionsView: View {
    @EnvironmentObject private var analytics: AnalyticsService

    var body: some View {
        NavigationStack {
            Group {
                if analytics.isLoading && analytics.appVersionStats.isEmpty {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if analytics.appVersionStats.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("By App Version")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if analytics.isLoading {
                        ProgressView()
                    } else {
                        Button { Task { await analytics.loadAll() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                summaryBanner
                    .padding()

                ForEach(analytics.appVersionStats) { stat in
                    AppVersionRow(stat: stat,
                                  maxUsers: analytics.appVersionStats.first?.activeUsers ?? 1)
                    Divider().padding(.leading, 20)
                }
            }
        }
    }

    // MARK: - Summary banner

    private var summaryBanner: some View {
        let totalUsers = analytics.appVersionStats.map(\.activeUsers).reduce(0, +)
        let versions = Set(analytics.appVersionStats.map(\.version)).count
        let latestVersion = analytics.appVersionStats
            .sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
            .first?.version ?? "—"

        return HStack(spacing: 0) {
            BannerStat(value: "\(totalUsers)", label: "Total Users", color: .blue)
            Divider().frame(height: 44)
            BannerStat(value: "\(versions)", label: "Versions", color: .purple)
            Divider().frame(height: 44)
            BannerStat(value: "v\(latestVersion)", label: "Latest", color: .green)
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "app.badge")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No version data available")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - App Version Row

private struct AppVersionRow: View {
    let stat: AppVersionStats
    let maxUsers: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                // Version badge
                Text("v\(stat.version)")
                    .font(.system(.headline, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(versionColor(stat.version).opacity(0.15), in: Capsule())
                    .foregroundStyle(versionColor(stat.version))

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(stat.activeUsers) users")
                        .font(.subheadline.bold())
                    Text("iOS \(stat.osVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07)).frame(height: 5)
                    Capsule()
                        .fill(versionColor(stat.version))
                        .frame(width: geo.size.width * CGFloat(stat.activeUsers) / CGFloat(maxUsers), height: 5)
                }
            }
            .frame(height: 5)

            // Stats row
            HStack(spacing: 0) {
                MiniStat(icon: "arrow.triangle.2.circlepath", value: "\(stat.sessions)", label: "Sessions")
                MiniStat(icon: "bolt.fill", value: stat.eventCount.abbreviated, label: "Events")
                MiniStat(icon: "exclamationmark.triangle.fill",
                         value: stat.crashes > 0 ? "\(stat.crashes)" : "0",
                         label: "Crashes",
                         color: stat.crashes > 0 ? .red : .secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func versionColor(_ version: String) -> Color {
        let colors: [Color] = [.blue, .purple, .teal, .orange, .pink, .green, .indigo]
        let hash = version.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return colors[hash % colors.count]
    }
}

// MARK: - Mini helpers

private struct MiniStat: View {
    let icon: String
    let value: String
    let label: String
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(value)
                .font(.caption.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BannerStat: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
