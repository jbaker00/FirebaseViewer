import SwiftUI

struct AppStoreStatsView: View {
    @EnvironmentObject private var asc: AppStoreConnectService

    var body: some View {
        NavigationStack {
            ScrollView {
                if !asc.isConfigured {
                    notConfiguredView
                } else if asc.isLoading && asc.apps.isEmpty {
                    loadingView
                } else if let err = asc.error {
                    errorView(message: err)
                } else {
                    contentView
                }
            }
            .navigationTitle("App Store Stats")
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
            appsSection
            if !asc.overview.countryStats.isEmpty {
                topCountries
            }
            if !asc.overview.dailySummaries.isEmpty {
                recentActivity
            }
        }
        .padding(.vertical)
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Apps")
                .font(.headline)
                .padding(.horizontal)

            if asc.apps.isEmpty {
                Text("No apps found")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                ForEach(asc.apps) { app in
                    HStack(spacing: 12) {
                        Image(systemName: "app.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .frame(width: 40, height: 40)
                            .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.attributes.name)
                                .font(.subheadline.bold())
                            Text(app.attributes.bundleId)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var topCountries: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Countries (Downloads)")
                .font(.headline)
                .padding(.horizontal)

            let top = Array(asc.overview.countryStats.prefix(15))
            let maxUnits = top.first?.totalUnits ?? 1

            ForEach(Array(top.enumerated()), id: \.element.id) { idx, item in
                VStack(spacing: 4) {
                    HStack {
                        Text("\(idx + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        Text(item.countryCode.flagEmoji)
                        Text(item.countryName)
                            .font(.subheadline)
                        Spacer()
                        Text("\(item.totalUnits)")
                            .font(.subheadline.bold())
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.07)).frame(height: 4)
                            Capsule()
                                .fill(barColor(rank: idx + 1))
                                .frame(width: geo.size.width * CGFloat(item.totalUnits) / CGFloat(maxUnits), height: 4)
                        }
                    }
                    .frame(height: 4)
                    .padding(.leading, 36)
                }
                .padding(.horizontal)
                .padding(.vertical, 2)
            }
        }
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Daily Activity")
                .font(.headline)
                .padding(.horizontal)

            let recent = asc.overview.dailySummaries.suffix(7).reversed()
            ForEach(Array(recent), id: \.id) { day in
                HStack {
                    Text(day.date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)

                    HStack(spacing: 16) {
                        Label("\(day.downloads)", systemImage: "arrow.down.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        Label("\(day.updates)", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    Spacer()
                    Text("\(day.totalUnits) total")
                        .font(.caption.bold())
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
            Text("Loading App Store Connect…")
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

    private func barColor(rank: Int) -> Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .blue.opacity(0.7)
        }
    }
}

private extension String {
    var flagEmoji: String {
        guard count == 2 else { return "" }
        let base: UInt32 = 127397
        var result = ""
        for scalar in uppercased().unicodeScalars {
            if let flag = Unicode.Scalar(base + scalar.value) {
                result.append(String(flag))
            }
        }
        return result
    }
}
