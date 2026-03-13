import SwiftUI

struct AdMobView: View {
    @EnvironmentObject private var service: AdMobService
    @State private var showEditPaidOutSheet = false
    @State private var editPaidOutText = ""

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
            .sheet(isPresented: $showEditPaidOutSheet) {
                editPaidOutSheetView
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
                // Summary cards at the top
                summaryCards

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

    // MARK: - Summary cards

    private var summaryCards: some View {
        HStack(spacing: 12) {
            // Paid Out card
            summaryBox(
                title: "Paid Out",
                amount: service.stats.paidOut,
                color: .green,
                icon: "checkmark.circle.fill",
                showEditButton: true
            )

            // To Be Collected card
            summaryBox(
                title: "To Be Collected",
                amount: service.stats.unpaidEarnings,
                color: .green,
                icon: "dollarsign.circle.fill",
                showEditButton: false
            )
        }
    }

    private func summaryBox(title: String, amount: Double, color: Color, icon: String, showEditButton: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with title and optional edit button
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                if showEditButton {
                    Button {
                        showEditPaidOutSheet = true
                    } label: {
                        Image(systemName: "pencil.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Amount
            Text(String(format: "$%.2f", amount))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

            // App breakdown for "To Be Collected"
            if !showEditButton && !service.allTimeAppStats.isEmpty {
                Divider()
                    .background(Color.white.opacity(0.3))

                VStack(alignment: .leading, spacing: 6) {
                    Text("By App")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 14)
                        .padding(.top, 8)

                    ForEach(service.allTimeAppStats.prefix(3)) { app in
                        HStack {
                            Text(app.appName)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1)
                            Spacer()
                            Text(String(format: "$%.2f", app.earnings))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 2)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .background(color.gradient)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
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

    // MARK: - Edit paid out sheet

    private var editPaidOutSheetView: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Paid Out Amount")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(String(format: "$%.2f", service.paidOutAmount))
                        .font(.title.bold())
                        .foregroundStyle(.green)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 12) {
                    Text("New Amount")
                        .font(.headline)

                    HStack {
                        Text("$")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $editPaidOutText)
                            .keyboardType(.decimalPad)
                            .font(.title2)
                            .textFieldStyle(.plain)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text("Enter the total amount that has been paid out to you from AdMob.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Edit Paid Out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showEditPaidOutSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let amount = Double(editPaidOutText) {
                            service.updatePaidOutAmount(amount)
                        }
                        showEditPaidOutSheet = false
                    }
                    .disabled(editPaidOutText.isEmpty || Double(editPaidOutText) == nil)
                }
            }
            .onAppear {
                editPaidOutText = String(format: "%.2f", service.paidOutAmount)
            }
        }
    }
}
