import SwiftUI

struct ContentView: View {
    @StateObject private var analytics = AnalyticsService()
    @StateObject private var admob = AdMobService()
    @StateObject private var config = ConfigurationService.shared

    @State private var showSetup = false

    var body: some View {
        Group {
            if showSetup {
                SetupView(config: config) {
                    withAnimation { showSetup = false }
                }
            } else {
                mainTabs
            }
        }
        .onAppear {
            if !config.isConfigured && !hasBundledServiceAccount() {
                showSetup = true
            }
        }
    }

    private var mainTabs: some View {
        TabView {
            AdMobView()
                .tabItem { Label("AdMob",        systemImage: "dollarsign.circle.fill") }
            AdMobMapView()
                .tabItem { Label("Revenue Map",  systemImage: "map.fill") }
            AppCountryView()
                .tabItem { Label("By Country",   systemImage: "globe.americas.fill") }
            DashboardView()
                .tabItem { Label("Dashboard",    systemImage: "chart.bar.fill") }
            MapView()
                .tabItem { Label("User Map",     systemImage: "person.3.fill") }
            AppVersionsView()
                .tabItem { Label("Versions",     systemImage: "app.badge.fill") }
            DatabaseView()
                .tabItem { Label("Database",     systemImage: "cylinder.split.1x2") }
            ErrorLogsView()
                .tabItem { Label("Errors",       systemImage: "exclamationmark.triangle.fill") }
            SettingsView(config: config) { showSetup = true }
                .tabItem { Label("Settings",     systemImage: "gear") }
            LogView()
                .tabItem { Label("Logs",         systemImage: "scroll.fill") }
        }
        .environmentObject(analytics)
        .environmentObject(admob)
        .task {
            async let analyticsLoad: () = analytics.loadAll()
            async let admobLoad: ()     = admob.loadStats()
            _ = await (analyticsLoad, admobLoad)
        }
    }

    /// Check if bundled ServiceAccount.json exists (original app behavior).
    private func hasBundledServiceAccount() -> Bool {
        Bundle.main.url(forResource: "ServiceAccount", withExtension: "json") != nil
    }
}
