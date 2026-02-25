import SwiftUI

struct ContentView: View {
    @StateObject private var analytics = AnalyticsService()
    @StateObject private var admob = AdMobService()

    var body: some View {
        VStack(spacing: 0) {
            ProjectPickerView()
                .environmentObject(analytics)

            TabView {
                DashboardView()
                    .tabItem {
                        Label("Dashboard", systemImage: "chart.bar.fill")
                    }
                AdMobView()
                    .tabItem {
                        Label("AdMob", systemImage: "dollarsign.circle.fill")
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
                LogView()
                    .tabItem {
                        Label("Logs", systemImage: "scroll.fill")
                    }
            }
        }
        .environmentObject(analytics)
        .environmentObject(admob)
        .task {
            async let analyticsLoad = analytics.loadAll()
            async let admobLoad     = admob.loadStats()
            _ = await (analyticsLoad, admobLoad)
        }
    }
}

