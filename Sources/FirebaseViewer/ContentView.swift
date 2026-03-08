import SwiftUI

struct ContentView: View {
    @StateObject private var analytics = AnalyticsService()
    @StateObject private var admob = AdMobService()
    @StateObject private var appStore = AppStoreConnectService()

    var body: some View {
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
            DownloadsView()
                .tabItem { Label("Downloads",    systemImage: "arrow.down.circle.fill") }
            AppStoreMapView()
                .tabItem { Label("Store Map",    systemImage: "map.circle.fill") }
            AppStoreStatsView()
                .tabItem { Label("App Store",    systemImage: "bag.fill") }
            DatabaseView()
                .tabItem { Label("Database",     systemImage: "cylinder.split.1x2") }
            ErrorLogsView()
                .tabItem { Label("Errors",       systemImage: "exclamationmark.triangle.fill") }
            LogView()
                .tabItem { Label("Logs",         systemImage: "scroll.fill") }
        }
        .environmentObject(analytics)
        .environmentObject(admob)
        .environmentObject(appStore)
        .task {
            appStore.configure()
            async let analyticsLoad: () = analytics.loadAll()
            async let admobLoad: ()     = admob.loadStats()
            async let ascLoad: ()       = appStore.loadAll()
            _ = await (analyticsLoad, admobLoad, ascLoad)
        }
    }
}
