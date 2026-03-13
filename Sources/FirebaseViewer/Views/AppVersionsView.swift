import SwiftUI

// MARK: - Tab Picker

enum VersionsTab: String, CaseIterable, Identifiable {
    case grouped   = "Grouped"
    case location  = "Location"
    case revenue   = "Revenue"
    case health    = "Health"
    case adoption  = "Adoption"

    var id: String { rawValue }
}

// MARK: - Container

struct AppVersionsView: View {
    @EnvironmentObject private var analytics: AnalyticsService
    @EnvironmentObject private var admob: AdMobService
    @State private var selectedTab: VersionsTab = .grouped

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                picker
                Divider()

                Group {
                    if analytics.isLoading && analytics.appVersionStats.isEmpty {
                        ProgressView("Loading…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if analytics.appVersionStats.isEmpty {
                        emptyState
                    } else {
                        tabContent
                    }
                }
            }
            .navigationTitle("Versions")
#if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if analytics.isLoading {
                        ProgressView()
                    } else {
                        Button { Task { await analytics.loadAll() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
    }

    private var picker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(VersionsTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
                    } label: {
                        Text(tab.rawValue)
                            .font(.subheadline.weight(selectedTab == tab ? .bold : .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                selectedTab == tab
                                    ? Color.accentColor.opacity(0.15)
                                    : Color.clear,
                                in: Capsule()
                            )
                            .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .grouped:  GroupedByVersionView()
        case .location: VersionsByLocationView()
        case .revenue:  VersionsByRevenueView()
        case .health:   VersionHealthView()
        case .adoption: VersionAdoptionView()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "app.badge")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No version data available")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Shared helpers used across version sub-views

func versionColor(_ version: String) -> Color {
    let colors: [Color] = [.blue, .purple, .teal, .orange, .pink, .green, .indigo]
    let hash = version.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    return colors[hash % colors.count]
}

struct VersionBadge: View {
    let version: String
    var body: some View {
        Text("v\(version)")
            .font(.system(.caption, design: .monospaced).bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(versionColor(version).opacity(0.15), in: Capsule())
            .foregroundStyle(versionColor(version))
    }
}

struct MiniStat: View {
    let icon: String
    let value: String
    let label: String
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(value)
                .font(.caption.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct BannerStat: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
