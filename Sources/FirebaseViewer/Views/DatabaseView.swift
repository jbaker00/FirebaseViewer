import SwiftUI

struct DatabaseView: View {
    @EnvironmentObject private var analytics: AnalyticsService

    var body: some View {
        NavigationStack {
            ScrollView {
                if analytics.isLoading && analytics.firestoreStats.isEmpty {
                    ProgressView("Loading database stats…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if analytics.firestoreStats.isEmpty {
                    noDataView
                } else {
                    collectionsGrid
                }
            }
            .navigationTitle("Database")
#if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .background(Color.platformSystemGroupedBackground)
            .refreshable { await analytics.loadAll() }
        }
    }

    // MARK: - Subviews

    private var collectionsGrid: some View {
        LazyVStack(spacing: 16) {
            // Summary header
            let total = analytics.firestoreStats.reduce(0) { $0 + $1.documentCount }
            HStack(spacing: 16) {
                summaryCard(value: "\(analytics.firestoreStats.count)", label: "Collections", icon: "tray.full.fill", color: .green)
                summaryCard(value: "\(total)", label: "Total Documents", icon: "doc.fill", color: .blue)
            }
            .padding(.horizontal)
            .padding(.top)

            // Per-collection cards
            ForEach(analytics.firestoreStats) { col in
                collectionCard(col, maxCount: analytics.firestoreStats.first?.documentCount ?? 1)
            }
            .padding(.horizontal)
        }
        .padding(.bottom)
    }

    private func summaryCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func collectionCard(_ col: FirestoreCollectionStats, maxCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "tray.fill")
                    .foregroundStyle(.green)
                Text(col.name)
                    .font(.headline)
                Spacer()
                Text("\(col.documentCount)")
                    .font(.title3.bold())
                Text("docs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                let fraction = maxCount > 0 ? CGFloat(col.documentCount) / CGFloat(maxCount) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.green.opacity(0.15))
                        .frame(height: 8)
                    Capsule().fill(Color.green.gradient)
                        .frame(width: geo.size.width * fraction, height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var noDataView: some View {
        ContentUnavailableView(
            "No Database Data",
            systemImage: "cylinder.split.1x2",
            description: Text("Firestore stats are available for Resort Browser.\nSelect that app to see collection info.")
        )
        .padding(.top, 60)
    }
}
