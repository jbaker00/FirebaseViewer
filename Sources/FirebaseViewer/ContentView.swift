import SwiftUI

struct ContentView: View {
    @StateObject private var analytics = AnalyticsService()

    var body: some View {
        VStack(spacing: 0) {
            ProjectPickerView()
                .environmentObject(analytics)

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
                DatabaseView()
                    .tabItem {
                        Label("Database", systemImage: "cylinder.split.1x2")
                    }
                AdMobView()
                    .tabItem {
                        Label("AdMob", systemImage: "dollarsign.circle.fill")
                    }
                LogView()
                    .tabItem {
                        Label("Logs", systemImage: "scroll.fill")
                    }
            }
        }
        .environmentObject(analytics)
        .task {
            await analytics.loadAll()
        }
    }
}

