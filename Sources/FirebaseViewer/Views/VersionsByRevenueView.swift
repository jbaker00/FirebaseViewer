import SwiftUI

/// Shows version data cross-referenced with AdMob revenue data.
/// Since AdMob doesn't break down by app version directly, we show versions side-by-side
/// with per-app revenue and estimate revenue contribution based on user share.
struct VersionsByRevenueView: View {
    @EnvironmentObject private var analytics: AnalyticsService
    @EnvironmentObject private var admob: AdMobService

    // Aggregate stats per unique version
    private var versionAggregates: [VersionAggregate] {
        let dict = Dictionary(grouping: analytics.appVersionStats, by: \.version)
        let totalUsers = analytics.appVersionStats.map(\.activeUsers).reduce(0, +)
        let thirtyDayEarnings = admob.stats.totalEarnings
        let todayEarnings = admob.todayEarnings

        return dict.map { version, rows in
            let users = rows.map(\.activeUsers).reduce(0, +)
            let sessions = rows.map(\.sessions).reduce(0, +)
            let events = rows.map(\.eventCount).reduce(0, +)
            let userShare = totalUsers > 0 ? Double(users) / Double(totalUsers) : 0

            return VersionAggregate(
                version: version,
                users: users,
                sessions: sessions,
                events: events,
                userShare: userShare,
                estimatedRevenue30d: thirtyDayEarnings * userShare,
                estimatedRevenueToday: todayEarnings * userShare
            )
        }
        .sorted { $0.estimatedRevenue30d > $1.estimatedRevenue30d }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                explanationBanner
                    .padding(.horizontal)
                    .padding(.top)

                if !admob.isAuthorized {
                    notConnectedView
                } else if !admob.hasData && admob.isLoading {
                    ProgressView("Loading revenue data…")
                        .padding(.top, 40)
                } else {
                    revenueHeader
                        .padding(.horizontal)

                    ForEach(versionAggregates, id: \.version) { agg in
                        RevenueVersionCard(aggregate: agg,
                                           maxRevenue: versionAggregates.first?.estimatedRevenue30d ?? 1)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 16)
        }
    }

    private var explanationBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
            Text("Revenue is estimated proportionally based on each version's share of active users.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var revenueHeader: some View {
        HStack(spacing: 12) {
            revenueCard(label: "Today (est.)", amount: admob.todayEarnings, color: .green)
            revenueCard(label: "30 Days", amount: admob.stats.totalEarnings, color: .blue)
        }
    }

    private func revenueCard(label: String, amount: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(format: "$%.2f", amount))
                .font(.title3.bold())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
    }

    private var notConnectedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "dollarsign.circle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Connect AdMob on the AdMob tab to see revenue estimates by version.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

// MARK: - Models

private struct VersionAggregate {
    let version: String
    let users: Int
    let sessions: Int
    let events: Int
    let userShare: Double
    let estimatedRevenue30d: Double
    let estimatedRevenueToday: Double
}

// MARK: - Revenue Version Card

private struct RevenueVersionCard: View {
    let aggregate: VersionAggregate
    let maxRevenue: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VersionBadge(version: aggregate.version)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "$%.2f", aggregate.estimatedRevenue30d))
                        .font(.subheadline.bold())
                        .foregroundStyle(.green)
                        .monospacedDigit()
                    Text("30d est.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Revenue bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.green.opacity(0.1)).frame(height: 8)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [versionColor(aggregate.version), .green],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: maxRevenue > 0
                                ? geo.size.width * CGFloat(aggregate.estimatedRevenue30d / maxRevenue)
                                : 0,
                            height: 8
                        )
                }
            }
            .frame(height: 8)

            // Stats strip
            HStack(spacing: 16) {
                Label("\(aggregate.users) users", systemImage: "person.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(String(format: "%.0f%%", aggregate.userShare * 100), systemImage: "chart.pie.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "$%.4f today", aggregate.estimatedRevenueToday))
                    .font(.caption2)
                    .foregroundStyle(.green.opacity(0.8))
                    .monospacedDigit()
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.green.opacity(0.15), lineWidth: 1)
        )
    }
}
