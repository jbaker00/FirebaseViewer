import SwiftUI
import Charts

struct DownloadsView: View {
    @EnvironmentObject private var asc: AppStoreConnectService

    var body: some View {
        NavigationStack {
            ScrollView {
                if !asc.isConfigured {
                    notConfiguredView
                } else if asc.isLoading && asc.overview.dailySummaries.isEmpty {
                    loadingView
                } else if let err = asc.error {
                    errorView(message: err)
                } else {
                    contentView
                }
            }
            .navigationTitle("App Store Downloads")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if asc.isLoading {
                        ProgressView()
                    } else {
                        Button(action: { Task { await asc.loadAll() } }) {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Content

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 20) {
            statsGrid
            if !asc.overview.dailySummaries.isEmpty {
                downloadsChart
            }
            if !asc.overview.deviceBreakdown.isEmpty {
                deviceBreakdown
            }
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
                    title: "Downloads",
                    value: asc.overview.totalDownloads.abbreviated,
                    icon: "arrow.down.circle.fill",
                    color: .blue
                )
                StatsCardView(
                    title: "Updates",
                    value: asc.overview.totalUpdates.abbreviated,
                    icon: "arrow.triangle.2.circlepath",
                    color: .green
                )
                StatsCardView(
                    title: "Re-Downloads",
                    value: asc.overview.totalRedownloads.abbreviated,
                    icon: "arrow.clockwise.circle.fill",
                    color: .orange
                )
                StatsCardView(
                    title: "Countries",
                    value: "\(asc.overview.uniqueCountries)",
                    icon: "globe",
                    color: .purple
                )
            }
            .padding(.horizontal)
        }
    }

    private var downloadsChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Downloads Over Time")
                .font(.headline)
                .padding(.horizontal)

            Chart(asc.overview.dailySummaries) { day in
                BarMark(
                    x: .value("Date", day.date, unit: .day),
                    y: .value("Downloads", day.downloads)
                )
                .foregroundStyle(.blue.gradient)

                if day.redownloads > 0 {
                    BarMark(
                        x: .value("Date", day.date, unit: .day),
                        y: .value("Re-Downloads", day.redownloads)
                    )
                    .foregroundStyle(.orange.gradient)
                }
            }
            .chartYAxisLabel("Units")
            .chartLegend(position: .bottom)
            .frame(height: 220)
            .padding(.horizontal)
        }
    }

    private var deviceBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By Device")
                .font(.headline)
                .padding(.horizontal)

            let sorted = asc.overview.deviceBreakdown.sorted { $0.value > $1.value }
            ForEach(sorted, id: \.key) { device, count in
                HStack {
                    Image(systemName: deviceIcon(device))
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    Text(deviceLabel(device))
                        .font(.subheadline)
                    Spacer()
                    Text(count.abbreviated)
                        .font(.subheadline.bold())
                }
                .padding(.horizontal)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.5)
            Text("Loading App Store data…")
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
                Task { await asc.loadAll() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var notConfiguredView: some View {
        ContentUnavailableView(
            "App Store Connect Not Configured",
            systemImage: "key.fill",
            description: Text("Add AppStoreConnectConfig.json to Resources with your API key details.")
        )
        .padding(.top, 60)
    }

    // MARK: - Helpers

    private func deviceIcon(_ code: String) -> String {
        let lower = code.lowercased()
        if lower.contains("iphone") { return "iphone" }
        if lower.contains("ipad") { return "ipad" }
        if lower.contains("mac") || lower.contains("desktop") { return "desktopcomputer" }
        if lower.contains("apple tv") || lower.contains("tv") { return "appletv" }
        if lower.contains("watch") { return "applewatch" }
        return "apps.iphone"
    }

    private func deviceLabel(_ code: String) -> String {
        let lower = code.lowercased()
        if lower.contains("iphone") { return "iPhone" }
        if lower.contains("ipad") { return "iPad" }
        if lower.contains("mac") || lower.contains("desktop") { return "Mac" }
        if lower.contains("apple tv") || lower.contains("tv") { return "Apple TV" }
        if lower.contains("watch") { return "Apple Watch" }
        return code.isEmpty ? "Unknown" : code
    }
}
