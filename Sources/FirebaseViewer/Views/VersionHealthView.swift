import SwiftUI

/// Scorecard showing per-version health metrics: crash rate, engagement, sessions per user.
struct VersionHealthView: View {
    @EnvironmentObject private var analytics: AnalyticsService

    private var healthScores: [VersionHealth] {
        let dict = Dictionary(grouping: analytics.appVersionStats, by: \.version)
        return dict.map { version, rows in
            let users = rows.map(\.activeUsers).reduce(0, +)
            let sessions = rows.map(\.sessions).reduce(0, +)
            let events = rows.map(\.eventCount).reduce(0, +)
            let crashes = rows.map(\.crashes).reduce(0, +)

            let crashRate = users > 0 ? Double(crashes) / Double(users) * 100 : 0
            let sessionsPerUser = users > 0 ? Double(sessions) / Double(users) : 0
            let eventsPerSession = sessions > 0 ? Double(events) / Double(sessions) : 0

            // Health score: 0-100. Penalise high crash rate, reward engagement.
            let crashPenalty = min(crashRate * 10, 50) // up to 50 points lost
            let engagementBonus = min(sessionsPerUser * 5, 30) // up to 30 points
            let activityBonus = min(eventsPerSession * 0.5, 20) // up to 20 points
            let score = max(0, min(100, 50 - crashPenalty + engagementBonus + activityBonus))

            return VersionHealth(
                version: version,
                users: users,
                sessions: sessions,
                events: events,
                crashes: crashes,
                crashRate: crashRate,
                sessionsPerUser: sessionsPerUser,
                eventsPerSession: eventsPerSession,
                healthScore: score
            )
        }
        .sorted { $0.healthScore > $1.healthScore }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                overviewGrid
                    .padding(.horizontal)
                    .padding(.top)

                ForEach(healthScores, id: \.version) { health in
                    HealthCard(health: health)
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 16)
        }
    }

    private var overviewGrid: some View {
        let bestVersion = healthScores.first
        let worstVersion = healthScores.last
        let totalCrashes = healthScores.map(\.crashes).reduce(0, +)
        let avgCrashRate = healthScores.isEmpty ? 0 :
            healthScores.map(\.crashRate).reduce(0, +) / Double(healthScores.count)

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatsCardView(
                title: "Healthiest",
                value: bestVersion.map { "v\($0.version)" } ?? "—",
                icon: "heart.fill",
                color: .green
            )
            StatsCardView(
                title: "Needs Attention",
                value: worstVersion.map { "v\($0.version)" } ?? "—",
                icon: "heart.slash.fill",
                color: .red
            )
            StatsCardView(
                title: "Total Crashes",
                value: totalCrashes.abbreviated,
                icon: "exclamationmark.triangle.fill",
                color: .orange
            )
            StatsCardView(
                title: "Avg Crash Rate",
                value: String(format: "%.1f%%", avgCrashRate),
                icon: "chart.line.downtrend.xyaxis",
                color: .purple
            )
        }
    }
}

// MARK: - Model

private struct VersionHealth {
    let version: String
    let users: Int
    let sessions: Int
    let events: Int
    let crashes: Int
    let crashRate: Double        // percentage
    let sessionsPerUser: Double
    let eventsPerSession: Double
    let healthScore: Double      // 0-100
}

// MARK: - Health Card

private struct HealthCard: View {
    let health: VersionHealth

    private var scoreColor: Color {
        switch health.healthScore {
        case 75...: return .green
        case 50...: return .yellow
        case 25...: return .orange
        default:    return .red
        }
    }

    private var scoreEmoji: String {
        switch health.healthScore {
        case 75...: return "💚"
        case 50...: return "💛"
        case 25...: return "🧡"
        default:    return "❤️‍🩹"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VersionBadge(version: health.version)
                Spacer()
                HStack(spacing: 6) {
                    Text(scoreEmoji)
                    Text(String(format: "%.0f", health.healthScore))
                        .font(.title2.bold())
                        .foregroundStyle(scoreColor)
                    Text("/ 100")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Health bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07)).frame(height: 8)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [scoreColor, scoreColor.opacity(0.6)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(health.healthScore / 100), height: 8)
                }
            }
            .frame(height: 8)

            // Metric grid
            HStack(spacing: 0) {
                metricCell(
                    label: "Crash Rate",
                    value: String(format: "%.1f%%", health.crashRate),
                    icon: "exclamationmark.triangle.fill",
                    highlight: health.crashRate > 5 ? .red : .secondary
                )
                metricCell(
                    label: "Sess/User",
                    value: String(format: "%.1f", health.sessionsPerUser),
                    icon: "arrow.triangle.2.circlepath",
                    highlight: health.sessionsPerUser > 2 ? .green : .secondary
                )
                metricCell(
                    label: "Events/Sess",
                    value: String(format: "%.0f", health.eventsPerSession),
                    icon: "bolt.fill",
                    highlight: health.eventsPerSession > 20 ? .green : .secondary
                )
                metricCell(
                    label: "Users",
                    value: health.users.abbreviated,
                    icon: "person.fill",
                    highlight: .blue
                )
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(scoreColor.opacity(0.25), lineWidth: 1)
        )
    }

    private func metricCell(label: String, value: String, icon: String, highlight: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(highlight)
            Text(value)
                .font(.caption.bold())
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
