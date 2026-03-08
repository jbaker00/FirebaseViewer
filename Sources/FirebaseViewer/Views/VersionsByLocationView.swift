import SwiftUI

/// Shows version adoption broken down by country — which countries are on which versions.
struct VersionsByLocationView: View {
    @EnvironmentObject private var analytics: AnalyticsService

    // Group by country → list of (version, users)
    private var countryGroups: [CountryVersionGroup] {
        let dict = Dictionary(grouping: analytics.versionCountryStats, by: \.country)
        return dict.map { country, rows in
            let versions = rows.map { VersionSlice(version: $0.version, users: $0.activeUsers) }
                .sorted { $0.users > $1.users }
            let total = versions.map(\.users).reduce(0, +)
            return CountryVersionGroup(country: country, totalUsers: total, versions: versions)
        }
        .sorted { $0.totalUsers > $1.totalUsers }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerBanner
                    .padding()

                if analytics.versionCountryStats.isEmpty {
                    noDataView
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(countryGroups.prefix(25).enumerated()), id: \.element.id) { idx, group in
                            CountryVersionCard(rank: idx + 1, group: group,
                                               globalMax: countryGroups.first?.totalUsers ?? 1)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    private var headerBanner: some View {
        let countries = countryGroups.count
        let topCountry = countryGroups.first?.country ?? "—"
        let uniqueVersions = Set(analytics.versionCountryStats.map(\.version)).count

        return HStack(spacing: 0) {
            BannerStat(value: "\(countries)", label: "Countries", color: .blue)
            Divider().frame(height: 44)
            BannerStat(value: "\(uniqueVersions)", label: "Versions", color: .purple)
            Divider().frame(height: 44)
            BannerStat(value: topCountry, label: "Top Country", color: .green)
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var noDataView: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No location × version data yet")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

// MARK: - Models

private struct VersionSlice: Identifiable {
    let id = UUID()
    let version: String
    let users: Int
}

private struct CountryVersionGroup: Identifiable {
    let id = UUID()
    let country: String
    let totalUsers: Int
    let versions: [VersionSlice]
}

// MARK: - Country Card

private struct CountryVersionCard: View {
    let rank: Int
    let group: CountryVersionGroup
    let globalMax: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Country header
            HStack {
                rankBadge
                Text(group.country)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(group.totalUsers) users")
                    .font(.caption.bold())
                    .monospacedDigit()
            }

            // Stacked horizontal bar showing version distribution
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(group.versions) { slice in
                        let fraction = CGFloat(slice.users) / CGFloat(group.totalUsers)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(versionColor(slice.version))
                            .frame(width: max(2, geo.size.width * fraction))
                    }
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())

            // Version pills
            FlowLayout(spacing: 6) {
                ForEach(group.versions.prefix(5)) { slice in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(versionColor(slice.version))
                            .frame(width: 8, height: 8)
                        Text("v\(slice.version)")
                            .font(.system(.caption2, design: .monospaced))
                        Text("\(slice.users)")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.05), in: Capsule())
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var rankBadge: some View {
        Text("\(rank)")
            .font(.caption2.bold())
            .frame(width: 22, height: 22)
            .background(rankColor.opacity(0.15), in: Circle())
            .foregroundStyle(rankColor)
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

// MARK: - Simple FlowLayout for version pills

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(in: proposal.width ?? .infinity, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                                  proposal: .unspecified)
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x)
        }

        return (origins, CGSize(width: maxWidth, height: y + rowHeight))
    }
}
