import SwiftUI

struct AdMobView: View {
    @StateObject private var service = AdMobService()

    var body: some View {
        NavigationStack {
            Group {
                if !service.isAuthorized {
                    signInView
                } else if service.isLoading {
                    ProgressView("Loading AdMob stats…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let err = service.error {
                    errorView(err)
                } else {
                    statsView
                }
            }
            .navigationTitle("AdMob")
            .navigationBarTitleDisplayMode(.large)
            .background(Color(.systemGroupedBackground))
            .refreshable {
                if service.isAuthorized { await service.loadStats() }
            }
            .task {
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
            LazyVStack(spacing: 16) {
                // Summary cards
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    statCard(
                        value: String(format: "$%.2f", service.stats.totalEarnings),
                        label: "30-Day Revenue",
                        icon: "dollarsign.circle.fill",
                        color: .green
                    )
                    statCard(
                        value: formatNumber(service.stats.impressions),
                        label: "Impressions",
                        icon: "eye.fill",
                        color: .blue
                    )
                    statCard(
                        value: formatNumber(service.stats.clicks),
                        label: "Clicks",
                        icon: "cursorarrow.click.2",
                        color: .orange
                    )
                    statCard(
                        value: String(format: "$%.2f", service.stats.ecpm),
                        label: "eCPM",
                        icon: "chart.bar.fill",
                        color: .purple
                    )
                }
                .padding(.horizontal)
                .padding(.top)

                // Per-app breakdown
                if !service.appStats.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("By App")
                            .font(.headline)
                            .padding(.horizontal)
                        ForEach(service.appStats) { app in
                            appRow(app)
                        }
                    }
                    .padding(.horizontal)
                }

                // Sign out
                Button("Disconnect AdMob", role: .destructive) {
                    service.signOut()
                }
                .padding()
            }
            .padding(.bottom)
        }
    }

    private func statCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title2.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func appRow(_ app: AdMobAppStats) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(app.appName)
                    .font(.subheadline.bold())
                Text("\(formatNumber(app.impressions)) impressions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "$%.2f", app.earnings))
                .font(.headline)
                .foregroundStyle(.green)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

    // MARK: - Helpers

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n)/1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n)/1_000) }
        return "\(n)"
    }
}
