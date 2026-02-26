import SwiftUI

struct ContentView: View {
    @StateObject private var credentialStore: CredentialStore
    @StateObject private var analytics: AnalyticsService
    @StateObject private var admob: AdMobService

    init() {
        let store = CredentialStore()
        _credentialStore = StateObject(wrappedValue: store)
        _analytics       = StateObject(wrappedValue: AnalyticsService(credentialStore: store))
        _admob           = StateObject(wrappedValue: AdMobService(credentialStore: store))
    }

    var body: some View {
        Group {
            if credentialStore.hasProjects {
                mainTabView
            } else {
                OnboardingView()
            }
        }
        .environmentObject(credentialStore)
        .environmentObject(analytics)
        .environmentObject(admob)
        .task {
            guard credentialStore.hasProjects else { return }
            async let analyticsLoad: () = analytics.loadAll()
            async let admobLoad: ()     = admob.loadStats()
            _ = await (analyticsLoad, admobLoad)
        }
        .onChange(of: credentialStore.projects) { _, _ in
            analytics.reloadProjects()
        }
    }

    private var mainTabView: some View {
        TabView {
            AdMobView()
                .tabItem { Label("AdMob",       systemImage: "dollarsign.circle.fill") }
            DashboardView()
                .tabItem { Label("Dashboard",   systemImage: "chart.bar.fill") }
            MapView()
                .tabItem { Label("User Map",    systemImage: "person.3.fill") }
            AdMobMapView()
                .tabItem { Label("Revenue Map", systemImage: "map.fill") }
            AppVersionsView()
                .tabItem { Label("Versions",    systemImage: "app.badge.fill") }
            DatabaseView()
                .tabItem { Label("Database",    systemImage: "cylinder.split.1x2") }
            LogView()
                .tabItem { Label("Logs",        systemImage: "scroll.fill") }
            SettingsView()
                .tabItem { Label("Settings",    systemImage: "gearshape.fill") }
        }
    }
}

