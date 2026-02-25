import SwiftUI
import MapKit

struct AdMobMapView: View {
    @EnvironmentObject private var service: AdMobService
    @State private var selected: AdMobCountryStats?
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            Group {
                if !service.isAuthorized {
                    ContentUnavailableView(
                        "AdMob Not Connected",
                        systemImage: "dollarsign.circle",
                        description: Text("Sign in on the AdMob tab to see revenue by country.")
                    )
                } else if service.countryStats.isEmpty && service.isLoading {
                    ProgressView("Loading revenue map…")
                } else if service.countryStats.isEmpty {
                    ContentUnavailableView(
                        "No Country Data",
                        systemImage: "map",
                        description: Text("No AdMob country earnings found.")
                    )
                } else {
                    ZStack(alignment: .bottom) {
                        map
                        if let s = selected {
                            CountryRevenueBanner(item: s) { selected = nil }
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .padding(.bottom, 8)
                        }
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationTitle("Revenue Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { withAnimation { cameraPosition = .automatic } } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                }
            }
        }
    }

    private var map: some View {
        let maxEarnings = service.countryStats.first?.earnings ?? 1
        return Map(position: $cameraPosition) {
            ForEach(service.countryStats) { item in
                if let coord = item.coordinate {
                    Annotation(item.countryCode, coordinate: CLLocationCoordinate2D(latitude: coord.lat, longitude: coord.lng)) {
                        RevenueBubble(
                            earnings: item.earnings,
                            maxEarnings: maxEarnings,
                            isSelected: selected?.id == item.id
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3)) { selected = item }
                        }
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
    }
}

// MARK: - Revenue Bubble

private struct RevenueBubble: View {
    let earnings: Double
    let maxEarnings: Double
    let isSelected: Bool

    private var ratio: Double { earnings / maxEarnings }

    private var size: CGFloat {
        let min: CGFloat = 18, max: CGFloat = 58
        return min + (max - min) * CGFloat(pow(ratio, 0.4))
    }

    private var color: Color {
        switch ratio {
        case 0.5...: return .green
        case 0.15...: return .mint
        case 0.03...: return .teal
        default:     return .blue
        }
    }

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.3)).frame(width: size * 1.5, height: size * 1.5)
            Circle().fill(color.opacity(0.8)).frame(width: size, height: size)
                .overlay(Circle().stroke(isSelected ? Color.white : Color.clear, lineWidth: 3))
            if size > 28 {
                Text(earnings.revenueLabel)
                    .font(.system(size: max(7, size * 0.26), weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .scaleEffect(isSelected ? 1.25 : 1.0)
        .animation(.spring(response: 0.2), value: isSelected)
        .shadow(color: color.opacity(0.5), radius: 6)
    }
}

// MARK: - Country Banner

private struct CountryRevenueBanner: View {
    let item: AdMobCountryStats
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.countryName)
                    .font(.headline)
                Text("\(item.impressions.formatted()) impressions · all time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "$%.2f", item.earnings))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.green)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
        }
        .padding()
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
        .shadow(radius: 12, y: 4)
    }
}

// MARK: - Helpers

private extension Double {
    /// Compact dollar label for bubble e.g. "$1.2" or "$0.38"
    var revenueLabel: String {
        if self >= 1 { return String(format: "$%.1f", self) }
        return String(format: "$%.2f", self)
    }
}
