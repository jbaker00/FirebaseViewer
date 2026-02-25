import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var analytics: AnalyticsService

    var body: some View {
        NavigationStack {
            ScrollView {
                if analytics.isLoading && analytics.countryData.isEmpty {
                    loadingView
                } else if !analytics.selectedProject.hasAnalytics {
                    noAnalyticsView
                } else if let err = analytics.error {
                    errorView(message: err)
                } else {
                    contentView
                }
            }
            .navigationTitle("Firebase Analytics")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if analytics.isLoading {
                        ProgressView()
                    } else {
                        Button(action: { Task { await analytics.loadAll() } }) {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 20) {
            statsGrid
            Divider().padding(.horizontal)
            countryList
        }
        .padding(.vertical)
    }

    private var statsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 30 Days")
                .font(.headline)
                .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatsCardView(
                    title: "Active Users",
                    value: analytics.stats.activeUsers.abbreviated,
                    icon: "person.fill",
                    color: .blue
                )
                StatsCardView(
                    title: "New Users",
                    value: analytics.stats.newUsers.abbreviated,
                    icon: "person.badge.plus",
                    color: .green
                )
                StatsCardView(
                    title: "Sessions",
                    value: analytics.stats.sessions.abbreviated,
                    icon: "iphone.and.arrow.forward",
                    color: .orange
                )
                StatsCardView(
                    title: "Events",
                    value: analytics.stats.eventCount.abbreviated,
                    icon: "bolt.fill",
                    color: .purple
                )
                StatsCardView(
                    title: "Screen Views",
                    value: analytics.stats.screenViews.abbreviated,
                    icon: "eye.fill",
                    color: .teal
                )
                StatsCardView(
                    title: "Countries",
                    value: "\(analytics.countryData.count)",
                    icon: "globe",
                    color: .pink
                )
            }
            .padding(.horizontal)
        }
    }

    private var countryList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Users by Country")
                .font(.headline)
                .padding(.horizontal)

            if analytics.countryData.isEmpty {
                Text("No country data available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                let maxUsers = analytics.countryData.first?.userCount ?? 1
                ForEach(Array(analytics.countryData.prefix(20).enumerated()), id: \.element.id) { idx, item in
                    CountryRowView(rank: idx + 1, item: item, maxUsers: maxUsers)
                        .padding(.horizontal)
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading analytics…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Could not load data")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Retry") {
                Task { await analytics.loadAll() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var noAnalyticsView: some View {
        ContentUnavailableView(
            "No Analytics Linked",
            systemImage: "chart.bar.xmark",
            description: Text("NJ Bus Scheduler doesn't have Google Analytics linked.\nSelect a different app to view stats.")
        )
        .padding(.top, 60)
    }
}

// MARK: - Country Row

private struct CountryRowView: View {
    let rank: Int
    let item: CountryUserCount
    let maxUsers: Int

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("\(rank)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)
                Text(item.country)
                    .font(.subheadline)
                Spacer()
                Text(item.userCount.abbreviated)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07)).frame(height: 4)
                    Capsule()
                        .fill(barColor(rank: rank))
                        .frame(width: geo.size.width * CGFloat(item.userCount) / CGFloat(maxUsers), height: 4)
                }
            }
            .frame(height: 4)
            .padding(.leading, 36)
        }
        .padding(.vertical, 4)
    }

    private func barColor(rank: Int) -> Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .blue.opacity(0.7)
        }
    }
}
