import SwiftUI

/// Shows version adoption as a stacked distribution chart and ranked list.
struct VersionAdoptionView: View {
    @EnvironmentObject private var analytics: AnalyticsService

    private var adoptionData: [VersionAdoption] {
        let dict = Dictionary(grouping: analytics.appVersionStats, by: \.version)
        let totalUsers = analytics.appVersionStats.map(\.activeUsers).reduce(0, +)

        return dict.map { version, rows in
            let users = rows.map(\.activeUsers).reduce(0, +)
            let share = totalUsers > 0 ? Double(users) / Double(totalUsers) : 0
            let osVersions = rows.map(\.osVersion)
            return VersionAdoption(version: version, users: users, share: share, osVersions: osVersions)
        }
        .sorted { $0.share > $1.share }
    }

    private var totalUsers: Int {
        analytics.appVersionStats.map(\.activeUsers).reduce(0, +)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                distributionChart
                    .padding(.horizontal)
                    .padding(.top)

                legendGrid
                    .padding(.horizontal)

                Divider()
                    .padding(.horizontal)

                adoptionList
                    .padding(.horizontal)
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Stacked Distribution Bar

    private var distributionChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Version Distribution")
                .font(.headline)

            // Big stacked bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(adoptionData, id: \.version) { item in
                        let width = max(3, geo.size.width * CGFloat(item.share))
                        RoundedRectangle(cornerRadius: 6)
                            .fill(versionColor(item.version).gradient)
                            .frame(width: width)
                    }
                }
            }
            .frame(height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Second bar: same data but showing cumulative adoption
            Text("Cumulative Adoption")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.05))

                    // Draw cumulative bands
                    let sorted = adoptionData.sorted {
                        $0.version.compare($1.version, options: .numeric) == .orderedDescending
                    }
                    ForEach(Array(sorted.enumerated()), id: \.element.version) { idx, item in
                        let cumulative = sorted.prefix(idx + 1).map(\.share).reduce(0, +)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(versionColor(item.version).opacity(0.8))
                            .frame(width: geo.size.width * CGFloat(cumulative))
                    }
                }
            }
            .frame(height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Legend Grid

    private var legendGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(adoptionData, id: \.version) { item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(versionColor(item.version))
                        .frame(width: 10, height: 10)
                    Text("v\(item.version)")
                        .font(.system(.caption2, design: .monospaced))
                    Text(String(format: "%.0f%%", item.share * 100))
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Adoption List

    private var adoptionList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ranked by Adoption")
                .font(.headline)

            ForEach(Array(adoptionData.enumerated()), id: \.element.version) { idx, item in
                AdoptionRow(rank: idx + 1, item: item, maxShare: adoptionData.first?.share ?? 1)
            }
        }
    }
}

// MARK: - Model

private struct VersionAdoption {
    let version: String
    let users: Int
    let share: Double // 0.0 - 1.0
    let osVersions: [String]
}

// MARK: - Adoption Row

private struct AdoptionRow: View {
    let rank: Int
    let item: VersionAdoption
    let maxShare: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Rank
                Text("#\(rank)")
                    .font(.caption.bold())
                    .foregroundStyle(rank <= 3 ? rankColor : .secondary)
                    .frame(width: 28, alignment: .trailing)

                VersionBadge(version: item.version)

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: "%.1f%%", item.share * 100))
                        .font(.subheadline.bold())
                    Text("\(item.users) users")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Proportional bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.05)).frame(height: 6)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [versionColor(item.version), versionColor(item.version).opacity(0.5)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: maxShare > 0
                                ? geo.size.width * CGFloat(item.share / maxShare)
                                : 0,
                            height: 6
                        )
                }
            }
            .frame(height: 6)
            .padding(.leading, 32)

            // OS versions this app version runs on
            if !item.osVersions.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                    Text(item.osVersions.sorted().joined(separator: ", "))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.leading, 32)
            }
        }
        .padding(.vertical, 4)
    }

    private var rankColor: Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .blue
        }
    }
}
