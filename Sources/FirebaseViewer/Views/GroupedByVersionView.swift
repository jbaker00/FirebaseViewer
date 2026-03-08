import SwiftUI

/// Groups version stats by unique version string, with OS breakdown inside each disclosure group.
struct GroupedByVersionView: View {
    @EnvironmentObject private var analytics: AnalyticsService

    private var grouped: [(version: String, rows: [AppVersionStats], totalUsers: Int)] {
        let dict = Dictionary(grouping: analytics.appVersionStats, by: \.version)
        return dict.map { version, rows in
            (version: version, rows: rows.sorted { $0.activeUsers > $1.activeUsers },
             totalUsers: rows.map(\.activeUsers).reduce(0, +))
        }
        .sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }

    private var totalUsers: Int {
        analytics.appVersionStats.map(\.activeUsers).reduce(0, +)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                summaryBanner
                    .padding()

                ForEach(grouped, id: \.version) { group in
                    VersionGroupCard(
                        version: group.version,
                        rows: group.rows,
                        totalUsers: group.totalUsers,
                        globalMaxUsers: grouped.first?.totalUsers ?? 1
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private var summaryBanner: some View {
        let versions = grouped.count
        let latestVersion = grouped.first?.version ?? "—"

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
}

// MARK: - Version Group Card

private struct VersionGroupCard: View {
    let version: String
    let rows: [AppVersionStats]
    let totalUsers: Int
    let globalMaxUsers: Int

    @State private var isExpanded = false

    private var totalSessions: Int { rows.map(\.sessions).reduce(0, +) }
    private var totalEvents: Int { rows.map(\.eventCount).reduce(0, +) }
    private var totalCrashes: Int { rows.map(\.crashes).reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — always visible
            Button { withAnimation(.easeInOut(duration: 0.25)) { isExpanded.toggle() } } label: {
                header
            }
            .buttonStyle(.plain)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07)).frame(height: 5)
                    Capsule()
                        .fill(versionColor(version))
                        .frame(width: geo.size.width * CGFloat(totalUsers) / CGFloat(globalMaxUsers),
                               height: 5)
                }
            }
            .frame(height: 5)
            .padding(.horizontal, 16)
            .padding(.top, 4)

            // Aggregate stats
            HStack(spacing: 0) {
                MiniStat(icon: "arrow.triangle.2.circlepath", value: totalSessions.abbreviated, label: "Sessions")
                MiniStat(icon: "bolt.fill", value: totalEvents.abbreviated, label: "Events")
                MiniStat(icon: "exclamationmark.triangle.fill",
                         value: totalCrashes > 0 ? "\(totalCrashes)" : "0",
                         label: "Crashes",
                         color: totalCrashes > 0 ? .red : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)

            // OS breakdown
            if isExpanded {
                Divider().padding(.horizontal, 16)
                VStack(spacing: 0) {
                    ForEach(rows) { stat in
                        HStack {
                            Image(systemName: "apple.logo")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("iOS \(stat.osVersion)")
                                .font(.subheadline)
                            Spacer()
                            Text("\(stat.activeUsers) users")
                                .font(.caption.bold())
                                .monospacedDigit()
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text("\(stat.sessions) sess")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            if stat.crashes > 0 {
                                Text("· \(stat.crashes) 💥")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(versionColor(version).opacity(0.2), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .center) {
            VersionBadge(version: version)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(totalUsers) users")
                    .font(.subheadline.bold())
                Text("\(rows.count) OS version\(rows.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }
}
