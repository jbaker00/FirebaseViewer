import SwiftUI
import MapKit

struct AppStoreMapView: View {
    @EnvironmentObject private var asc: AppStoreConnectService
    @State private var selected: AppStoreConnectCountryStats?
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            Group {
                if !asc.isConfigured {
                    ContentUnavailableView(
                        "App Store Connect Not Configured",
                        systemImage: "key.fill",
                        description: Text("Add AppStoreConnectConfig.json to Resources.")
                    )
                } else if asc.overview.countryStats.isEmpty && asc.isLoading {
                    ProgressView("Loading download map…")
                } else if asc.overview.countryStats.isEmpty {
                    ContentUnavailableView(
                        "No Country Data",
                        systemImage: "map",
                        description: Text("No App Store download data by country found.")
                    )
                } else {
                    mapWithOverlays
                }
            }
            .navigationTitle("Download Map")
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

    // MARK: - Map

    private var mapWithOverlays: some View {
        let countries = asc.overview.countryStats
        let maxUnits = countries.first?.totalUnits ?? 1

        return Map(position: $cameraPosition) {
            ForEach(countries) { item in
                if let coord = item.coordinate {
                    Annotation(item.countryName,
                               coordinate: CLLocationCoordinate2D(latitude: coord.lat, longitude: coord.lng)) {
                        DownloadBubble(
                            units: item.totalUnits,
                            maxUnits: maxUnits,
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
        .overlay(alignment: .bottom) {
            if let s = selected {
                CountryDownloadBanner(item: s) { selected = nil }
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: selected?.id)
    }
}

// MARK: - Download Bubble

private struct DownloadBubble: View {
    let units: Int
    let maxUnits: Int
    let isSelected: Bool

    private var ratio: Double { Double(units) / Double(maxUnits) }

    private var size: CGFloat {
        let min: CGFloat = 18, max: CGFloat = 58
        return min + (max - min) * CGFloat(pow(ratio, 0.4))
    }

    private let color = Color.blue

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.3)).frame(width: size * 1.5, height: size * 1.5)
            Circle().fill(color.opacity(0.8)).frame(width: size, height: size)
                .overlay(Circle().stroke(isSelected ? Color.white : Color.clear, lineWidth: 3))
            if size > 28 {
                Text("\(units)")
                    .font(.system(size: max(7, size * 0.26), weight: .bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
            }
        }
        .scaleEffect(isSelected ? 1.25 : 1.0)
        .animation(.spring(response: 0.2), value: isSelected)
        .shadow(color: color.opacity(0.5), radius: 6)
    }
}

// MARK: - Country Banner

private struct CountryDownloadBanner: View {
    let item: AppStoreConnectCountryStats
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        let flag = item.countryCode.flagEmoji
                        if !flag.isEmpty { Text(flag).font(.title2) }
                        Text(item.countryName).font(.headline)
                    }
                    Text("Last 30 days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(item.totalUnits)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                    Text("total units")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
            }

            Divider()
            HStack {
                Label("Downloads", systemImage: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(item.downloads)")
                    .font(.caption.bold())
            }
        }
        .padding()
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
        .shadow(radius: 12, y: 4)
    }
}

// MARK: - Flag helper

private extension String {
    var flagEmoji: String {
        guard count == 2 else { return "" }
        let base: UInt32 = 127397
        var result = ""
        for scalar in uppercased().unicodeScalars {
            if let flag = Unicode.Scalar(base + scalar.value) {
                result.append(String(flag))
            }
        }
        return result
    }
}
