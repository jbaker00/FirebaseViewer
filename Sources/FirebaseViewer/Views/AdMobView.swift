import SwiftUI

struct AdMobView: View {
    @EnvironmentObject private var service: AdMobService

    var body: some View {
        NavigationStack {
            Group {
                if !service.isAuthorized {
                    signInView
                } else if service.isLoading && service.multiPeriodReports.isEmpty {
                    ProgressView("Loading AdMob stats…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let err = service.error, service.multiPeriodReports.isEmpty {
                    errorView(err)
                } else {
                    statsView
                }
            }
            .navigationTitle("AdMob")
#if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .background(Color.platformSystemGroupedBackground)
            .refreshable {
                if service.isAuthorized { await service.loadStats() }
            }
        }
    }

    // MARK: - Sign-in screen

    private var signInView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.orange.gradient)
            Text("Connect AdMob")
                .font(.title.bold())
            Text("Sign in with Google to view your ad revenue, impressions, and more across all your apps.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Task { await service.signIn() }
            } label: {
                HStack {
                    Image(systemName: "person.badge.key.fill")
                    Text("Sign in with Google")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.orange.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)
            if let err = service.error {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
            Spacer()
        }
    }

    // MARK: - Stats screen

    private var statsView: some View {
        ScrollView {
            VStack(spacing: 20) {
                ForEach(service.multiPeriodReports, id: \.label) { report in
                    periodCard(report)
                }

                Button("Disconnect AdMob", role: .destructive) {
                    service.signOut()
                }
                .padding(.vertical, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Period card

    private func periodCard(_ report: AdMobPeriodReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ──
            HStack {
                Text(report.label)
                    .font(.title3.bold())
                Spacer()
                Text(String(format: "$%.2f", report.earnings))
                    .font(.title2.bold())
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.platformSecondarySystemGroupedBackground)

            Divider()

            // ── Metric strip ──
            HStack(spacing: 0) {
                metricPill(value: formatNumber(report.impressions),
                           label: "Impressions",
                           icon: "eye.fill", color: .blue)
                pillDivider()
                metricPill(value: formatNumber(report.clicks),
                           label: "Clicks",
                           icon: "cursorarrow.click.2", color: .orange)
                pillDivider()
                metricPill(value: formatNumber(report.adRequests),
                           label: "Requests",
                           icon: "antenna.radiowaves.left.and.right", color: .purple)
            }
            .padding(.vertical, 12)
            .background(Color.platformSystemBackground)

            // ── By App ──
            if !report.appBreakdown.isEmpty {
                Divider()
                disclosureCard(
                    label: "By App", icon: "iphone",
                    rows: report.appBreakdown.map { app in
                        BreakdownRow(name: app.name,
                                     detail: "\(formatNumber(app.impressions)) imp · \(formatNumber(app.clicks)) clicks",
                                     earnings: app.earnings)
                    }
                )
            }

            // ── By Country (hide $0 entries) ──
            let revenueCountries = report.countryBreakdown.filter { $0.earnings > 0 }
            if !revenueCountries.isEmpty {
                Divider()
                disclosureCard(
                    label: "By Country", icon: "globe",
                    rows: revenueCountries.map { c in
                        let flag = c.code.flagEmoji
                        let label = flag.isEmpty ? c.name : "\(flag) \(c.name)"
                        return BreakdownRow(name: label,
                                            detail: "\(formatNumber(c.impressions)) imp · \(formatNumber(c.clicks)) clicks",
                                            earnings: c.earnings)
                    }
                )
            }
        }
        .background(Color.platformSystemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.10), radius: 6, x: 0, y: 2)
    }

    // MARK: - Disclosure card

    private struct BreakdownRow {
        let name: String
        let detail: String
        let earnings: Double
    }

    private func disclosureCard(label: String, icon: String, rows: [BreakdownRow]) -> some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    if idx > 0 { Divider().padding(.leading, 16) }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(row.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(String(format: "$%.4f", row.earnings))
                            .font(.subheadline.bold())
                            .foregroundStyle(.green)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            .background(Color.platformSecondarySystemGroupedBackground)
        } label: {
            Label(label, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .tint(.primary)
    }

    // MARK: - Helpers

    private func metricPill(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline.bold())
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func pillDivider() -> some View {
        Divider()
            .frame(height: 36)
    }

    private func errorView(_ msg: String) -> some View {
        ContentUnavailableView {
            Label("Error Loading AdMob", systemImage: "exclamationmark.triangle")
        } description: {
            Text(msg)
        } actions: {
            Button("Retry") { Task { await service.loadStats() } }
                .buttonStyle(.bordered)
        }
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}
