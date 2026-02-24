import SwiftUI

struct ContentView: View {
    @StateObject private var analytics = AnalyticsService()

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar.fill")
                }
            MapView()
                .tabItem {
                    Label("User Map", systemImage: "map.fill")
                }
            AppVersionsView()
                .tabItem {
                    Label("Versions", systemImage: "app.badge.fill")
                }
        }
        .environmentObject(analytics)
        .task {
            await analytics.loadAll()
        }
    }
}
