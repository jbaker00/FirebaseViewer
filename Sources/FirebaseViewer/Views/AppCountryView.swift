import SwiftUI

/// Shows all-time AdMob impressions and revenue broken down by app, then by country.
struct AppCountryView: View {
    @EnvironmentObject private var service: AdMobService

    // MARK: - Data model

    struct AppEntry: Identifiable {
        let id = UUID()
        let appName: String
        let totalImpressions: Int
        let totalEarnings: Double
        let countries: [CountryEntry]

        struct CountryEntry: Identifiable {
            let id = UUID()
            let code: String   // ISO 3166-1 alpha-2
            let name: String
            let impressions: Int
            let earnings: Double
        }
    }

    // MARK: - Computed data

    private var appData: [AppEntry] {
        // Invert countryStats (country → apps) into app → countries
        // Value: (totalImp, totalEarn, [countryName: (code, imp, earn)])
        var appMap: [String: (imp: Int, earn: Double, countries: [String: (code: String, imp: Int, earn: Double)])] = [:]

        for country in service.countryStats {
            for app in country.appBreakdown where app.impressions > 0 {
                var entry = appMap[app.appName] ?? (0, 0.0, [:])
                entry.imp  += app.impressions
                entry.earn += app.earnings
                let prev = entry.countries[country.countryName] ?? (code: country.countryCode, imp: 0, earn: 0.0)
                entry.countries[country.countryName] = (code: country.countryCode,
                                                        imp:  prev.imp  + app.impressions,
                                                        earn: prev.earn + app.earnings)
                appMap[app.appName] = entry
            }
        }

        // Exclude retired app
        let excluded = AdMobMapView.excludedAppNames

        return appMap
            .filter { !excluded.contains($0.key) }
            .map { appName, data in
                AppEntry(
                    appName: appName,
                    totalImpressions: data.imp,
                    totalEarnings: data.earn,
                    countries: data.countries
                        .map { name, val in
                            AppEntry.CountryEntry(code: val.code, name: name,
                                                  impressions: val.imp, earnings: val.earn)
                        }
                        .sorted { $0.impressions > $1.impressions }
                )
            }
            .sorted { $0.totalImpressions > $1.totalImpressions }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if !service.isAuthorized {
                    ContentUnavailableView(
                        "AdMob Not Connected",
                        systemImage: "globe",
                        description: Text("Sign in on the AdMob tab to see app usage by country.")
                    )
                } else if service.isLoading && service.countryStats.isEmpty {
                    ProgressView("Loading…")
                } else if service.countryStats.isEmpty {
                    ContentUnavailableView("No Data", systemImage: "globe")
                } else {
                    list
                }
            }
            .navigationTitle("App by Country")
            .navigationBarTitleDisplayMode(.large)
            .refreshable { if service.isAuthorized { await service.loadStats() } }
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            ForEach(appData) { app in
                Section {
                    ForEach(app.countries) { country in
                        HStack(spacing: 12) {
                            Text(country.code.flagEmoji)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(country.name)
                                    .font(.subheadline.weight(.medium))
                                Text(formatImpressions(country.impressions))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if country.earnings > 0 {
                                Text(String(format: "$%.2f", country.earnings))
                                    .font(.caption.bold())
                                    .foregroundStyle(.green)
                                    .monospacedDigit()
                            }
                            Text(formatImpressions(country.impressions))
                                .font(.subheadline.bold())
                                .foregroundStyle(.blue)
                                .monospacedDigit()
                                .frame(width: 56, alignment: .trailing)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    HStack {
                        Text(app.appName)
                            .font(.subheadline.bold())
                            .textCase(nil)
                            .foregroundStyle(.primary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(formatImpressions(app.totalImpressions) + " imp")
                                .font(.caption.bold())
                                .foregroundStyle(.blue)
                            if app.totalEarnings > 0 {
                                Text(String(format: "$%.2f", app.totalEarnings))
                                    .font(.caption.bold())
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Helpers

    private func formatImpressions(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}
