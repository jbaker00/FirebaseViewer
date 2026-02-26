import Foundation
import SwiftUI

struct FirebaseProject: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    /// GA4 property ID, or nil if no analytics.
    let ga4PropertyID: String?
    /// One or more stream IDs to filter by. nil = all streams (no filter).
    let streamIDs: [String]?
    /// Firebase/GCP project ID for Firestore access, or nil.
    let firestoreProjectID: String?
    /// The app name as it appears in AdMob (displayLabel). nil = no AdMob for this app.
    let admobAppName: String?
    let icon: String
    let tintColor: ProjectColor

    var hasAnalytics: Bool { ga4PropertyID != nil }
    var hasFirestore: Bool { firestoreProjectID != nil }

    enum ProjectColor: String, Codable {
        case orange, blue, purple, green, red

        var color: Color {
            switch self {
            case .orange: return .orange
            case .blue:   return .blue
            case .purple: return .purple
            case .green:  return .green
            case .red:    return .red
            }
        }
    }

    static let availableIcons: [String] = [
        "tram.fill", "bus.fill", "car.fill", "airplane", "bicycle",
        "house.fill", "building.2.fill", "beach.umbrella.fill",
        "character.bubble.fill", "globe", "star.fill", "heart.fill",
        "bolt.fill", "flame.fill", "leaf.fill", "camera.fill",
        "gamecontroller.fill", "cart.fill", "fork.knife", "music.note",
        "books.vertical.fill", "doc.fill", "chart.bar.fill", "person.2.fill"
    ]
}
