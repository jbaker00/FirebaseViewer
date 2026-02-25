import SwiftUI
import MapKit

struct AdMobMapView: View {
    @EnvironmentObject private var service: AdMobService
    @State private var selected: AdMobCountryStats?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedApp: String? = nil  // nil = all apps

    /// Distinct app names across all countries, sorted by total earnings
    private var appNames: [String] {
        var totals: [String: Double] = [:]
        for country in service.countryStats {
            for app in country.appBreakdown {
                totals[app.appName, default: 0] += app.earnings
            }
        }
        return totals.sorted { $0.value > $1.value }.map { $0.key }
    }

    /// Countries filtered by the selected app (or all if nil)
    private var filteredCountries: [AdMobCountryStats] {
        guard let app = selectedApp else { return service.countryStats }
        return service.countryStats.compactMap { country in
            guard let entry = country.appBreakdown.first(where: { $0.appName == app }) else { return nil }
            // Return a version of the country with only the selected app's numbers for bubble sizing
            return AdMobCountryStats(
                countryCode: country.countryCode,
                countryName: country.countryName,
                earnings: entry.earnings,
                impressions: entry.impressions,
                appBreakdown: [entry]
            )
        }.sorted { $0.earnings > $1.earnings }
    }

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
                    mapWithOverlays
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

    // MARK: - Map + overlays

    private var mapWithOverlays: some View {
        let countries = filteredCountries
        let maxEarnings = countries.first?.earnings ?? 1

        return Map(position: $cameraPosition) {
            ForEach(countries) { item in
                if let coord = item.coordinate {
                    Annotation(item.countryCode,
                               coordinate: CLLocationCoordinate2D(latitude: coord.lat, longitude: coord.lng)) {
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
        .mapControls { MapCompass(); MapScaleView() }
        .ignoresSafeArea(edges: .bottom)
        // App filter chips — pinned to top of map
        .safeAreaInset(edge: .top, spacing: 0) {
            appFilterChips
        }
        // Banner — sits above the tab bar (respects safe area bottom)
        .overlay(alignment: .bottom) {
            if let s = selected {
                CountryRevenueBanner(item: s) { selected = nil }
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: selected?.id)
        .onChange(of: selectedApp) { _, _ in
            selected = nil
            withAnimation { cameraPosition = .automatic }
        }
    }

    // MARK: - Filter chips

    private var appFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(label: "All Apps", isSelected: selectedApp == nil) {
                    selectedApp = nil
                }
                ForEach(appNames, id: \.self) { name in
                    chip(label: name, isSelected: selectedApp == name) {
                        selectedApp = (selectedApp == name) ? nil : name
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    private func chip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(isSelected ? Color.green : Color(.systemFill))
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 10) {
            // Header row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.countryName)
                        .font(.headline)
                    Text("\(item.impressions.formatted()) impressions · all time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "$%.2f", item.earnings))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
            }

            // Per-app breakdown
            if item.appBreakdown.count > 1 {
                Divider()
                ForEach(item.appBreakdown) { app in
                    HStack {
                        Text(app.appName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(app.impressions) imp")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(String(format: "$%.4f", app.earnings))
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    }
                }
            } else if let only = item.appBreakdown.first {
                // Single app — show name inline
                Divider()
                HStack {
                    Image(systemName: "iphone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(only.appName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
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
