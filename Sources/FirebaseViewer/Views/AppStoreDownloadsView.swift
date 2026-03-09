import SwiftUI
import Charts

struct AppStoreDownloadsView: View {

    @StateObject private var service = AppStoreConnectService()

    // Setup-form fields
    @State private var keyID        = ""
    @State private var issuerID     = ""
    @State private var vendorNumber = ""
    @State private var privateKey   = ""

    var body: some View {
        NavigationStack {
            Group {
                if !service.isConfigured {
                    setupView
                } else if service.isLoading && service.summary.totalDownloads == 0 {
                    ProgressView("Loading App Store data…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let err = service.error, service.summary.totalDownloads == 0 {
                    errorView(err)
                } else {
                    downloadsView
                }
            }
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.large)
            .background(Color(.systemGroupedBackground))
            .refreshable {
                if service.isConfigured { await service.loadDownloads() }
            }
            .task {
                if service.isConfigured && service.summary.totalDownloads == 0 {
                    await service.loadDownloads()
                }
            }
        }
    }

    // MARK: - Setup screen

    private var setupView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)

                Image(systemName: "apple.logo")
                    .font(.system(size: 64))
                    .foregroundStyle(.primary)

                Text("Connect App Store")
                    .font(.title.bold())

                Text("Enter your App Store Connect API credentials to view download data for your apps over the last 30 days.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(spacing: 16) {
                    credentialField(
                        label: "Key ID", icon: "key.fill",
                        placeholder: "e.g. ABCDE12345",
                        text: $keyID
                    )
                    credentialField(
                        label: "Issuer ID", icon: "person.circle.fill",
                        placeholder: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
                        text: $issuerID
                    )
                    credentialField(
                        label: "Vendor Number", icon: "number",
                        placeholder: "e.g. 12345678",
                        text: $vendorNumber,
                        keyboardType: .numberPad
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Private Key (.p8 file content)", systemImage: "lock.doc.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        TextEditor(text: $privateKey)
                            .frame(minHeight: 130)
                            .font(.system(.caption, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(.systemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(.systemFill), lineWidth: 1)
                            )
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }
                .padding(.horizontal, 24)

                Button {
                    service.configure(
                        keyID:        keyID,
                        issuerID:     issuerID,
                        vendorNumber: vendorNumber,
                        privateKey:   privateKey
                    )
                    Task { await service.loadDownloads() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                        Text("Connect")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.black.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .disabled(keyID.isEmpty || issuerID.isEmpty || vendorNumber.isEmpty || privateKey.isEmpty)

                if let err = service.error {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 24)
                }

                Spacer()
            }
        }
    }

    // MARK: - Data screen

    private var downloadsView: some View {
        ScrollView {
            VStack(spacing: 20) {
                summaryCard

                if !service.summary.dailyDownloads.isEmpty {
                    trendChart
                }

                if !service.summary.appBreakdowns.isEmpty {
                    appsCard
                }

                if service.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Refreshing…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let err = service.error {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Button("Disconnect App Store", role: .destructive) {
                    service.disconnect()
                }
                .padding(.vertical, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Last 30 Days")
                    .font(.title3.bold())
                Spacer()
                Text(formatNumber(service.summary.totalDownloads))
                    .font(.title2.bold())
                    .foregroundStyle(.blue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground))

            Divider()

            HStack(spacing: 0) {
                metricPill(
                    value: formatNumber(service.summary.totalDownloads),
                    label: "Downloads",
                    icon: "arrow.down.app.fill",
                    color: .blue
                )
                if service.summary.totalProceeds > 0 {
                    pillDivider()
                    metricPill(
                        value: String(format: "$%.2f", service.summary.totalProceeds),
                        label: "Proceeds",
                        icon: "dollarsign.circle.fill",
                        color: .green
                    )
                }
            }
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.10), radius: 6, x: 0, y: 2)
    }

    // MARK: - Daily trend chart

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Downloads")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 14)

            Chart(service.summary.dailyDownloads) { day in
                BarMark(
                    x: .value("Date", day.date, unit: .day),
                    y: .value("Downloads", day.downloads)
                )
                .foregroundStyle(Color.blue.gradient)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
            .frame(height: 160)
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.10), radius: 6, x: 0, y: 2)
    }

    // MARK: - Per-app breakdown card

    private var appsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("By App")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()

            ForEach(Array(service.summary.appBreakdowns.enumerated()), id: \.offset) { idx, app in
                if idx > 0 { Divider().padding(.leading, 16) }
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.appTitle)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        if app.proceeds > 0 {
                            Text(String(format: "$%.2f proceeds", app.proceeds))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(formatNumber(app.downloads))
                        .font(.subheadline.bold())
                        .foregroundStyle(.blue)
                        .monospacedDigit()
                    Text("downloads")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.10), radius: 6, x: 0, y: 2)
    }

    // MARK: - Error view

    private func errorView(_ msg: String) -> some View {
        ContentUnavailableView {
            Label("Error Loading App Store Data", systemImage: "exclamationmark.triangle")
        } description: {
            Text(msg)
        } actions: {
            Button("Retry") { Task { await service.loadDownloads() } }
                .buttonStyle(.bordered)
            Button("Reconfigure") { service.disconnect() }
                .buttonStyle(.bordered)
        }
    }

    // MARK: - Helpers

    private func credentialField(label: String,
                                 icon: String,
                                 placeholder: String,
                                 text: Binding<String>,
                                 keyboardType: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .keyboardType(keyboardType)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
    }

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
        Divider().frame(height: 36)
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}
