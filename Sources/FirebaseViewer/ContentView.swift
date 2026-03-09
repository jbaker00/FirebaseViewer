import SwiftUI

struct ContentView: View {
    @StateObject private var googleSignIn: GoogleSignInService
    @StateObject private var analytics: AnalyticsService
    @StateObject private var errorLogs: ErrorLogsService
    @StateObject private var admob: AdMobService

    // Analytics and ErrorLogs services share the GoogleSignInService instance so
    // the user's OAuth token is preferred over any bundled service-account JSON,
    // eliminating the need for gcloud or a service-account key file.
    init() {
        let signIn = GoogleSignInService()
        _googleSignIn = StateObject(wrappedValue: signIn)
        _analytics    = StateObject(wrappedValue: AnalyticsService(googleSignIn: signIn))
        _errorLogs    = StateObject(wrappedValue: ErrorLogsService(googleSignIn: signIn))
        _admob        = StateObject(wrappedValue: AdMobService())
    }

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
            DatabaseView()
                .tabItem { Label("Database",     systemImage: "cylinder.split.1x2") }
            ErrorLogsView()
                .tabItem { Label("Errors",       systemImage: "exclamationmark.triangle.fill") }
            LogView()
                .tabItem { Label("Logs",         systemImage: "scroll.fill") }
            SettingsView()
                .tabItem { Label("Settings",     systemImage: "gearshape.fill") }
        }
        .environmentObject(analytics)
        .environmentObject(admob)
        .environmentObject(googleSignIn)
        .environmentObject(errorLogs)
        .task {
            async let analyticsLoad: () = analytics.loadAll()
            async let admobLoad: ()     = admob.loadStats()
            _ = await (analyticsLoad, admobLoad)
        }
    }
}
