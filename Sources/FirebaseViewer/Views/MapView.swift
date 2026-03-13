import SwiftUI
import MapKit

struct MapView: View {
    @EnvironmentObject private var analytics: AnalyticsService
    @State private var selectedCountry: CountryUserCount?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var showingDetail = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                worldMap
                if let selected = selectedCountry {
                    CountryDetailBanner(item: selected) {
                        selectedCountry = nil
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("User Map")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: resetCamera) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Map

    private var worldMap: some View {
        Map(position: $cameraPosition) {
            ForEach(analytics.countryData) { item in
                if let coord = item.coordinate {
                    Annotation(item.country, coordinate: CLLocationCoordinate2D(latitude: coord.lat, longitude: coord.lng)) {
                        UserBubble(
                            count: item.userCount,
                            maxCount: analytics.countryData.first?.userCount ?? 1,
                            isSelected: selectedCountry?.id == item.id
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3)) {
                                selectedCountry = item
                            }
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

    private func resetCamera() {
        withAnimation {
            cameraPosition = .automatic
        }
    }
}

// MARK: - User Bubble Annotation

private struct UserBubble: View {
    let count: Int
    let maxCount: Int
    let isSelected: Bool

    private var normalizedSize: CGFloat {
        let ratio = CGFloat(count) / CGFloat(maxCount)
        let minSize: CGFloat = 20
        let maxSize: CGFloat = 56
        return minSize + (maxSize - minSize) * pow(ratio, 0.45)
    }

    private var bubbleColor: Color {
        switch Double(count) / Double(maxCount) {
        case 0.5...: return .red
        case 0.2...: return .orange
        case 0.05...: return .yellow
        default:     return .blue
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(bubbleColor.opacity(0.35))
                .frame(width: normalizedSize * 1.4, height: normalizedSize * 1.4)
            Circle()
                .fill(bubbleColor.opacity(0.75))
                .frame(width: normalizedSize, height: normalizedSize)
                .overlay(
                    Circle().stroke(isSelected ? Color.white : Color.clear, lineWidth: 3)
                )
            if normalizedSize > 30 {
                Text(count.abbreviated)
                    .font(.system(size: max(8, normalizedSize * 0.28), weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .scaleEffect(isSelected ? 1.2 : 1.0)
        .animation(.spring(response: 0.2), value: isSelected)
        .shadow(color: bubbleColor.opacity(0.5), radius: 6)
    }
}

// MARK: - Country Detail Banner

private struct CountryDetailBanner: View {
    let item: CountryUserCount
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.country)
                    .font(.headline)
                Text("Active Users (30d)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.userCount.abbreviated)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.blue)
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
