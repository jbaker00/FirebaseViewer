import Foundation
import SwiftUI

struct FirebaseProject: Identifiable, Equatable {
    let id: String
    let name: String
    /// GA4 property ID, or nil if no analytics.
    let ga4PropertyID: String?
    /// One or more stream IDs to filter by. nil = all streams (no filter).
    let streamIDs: [String]?
    /// Firebase/GCP project ID for Firestore access, or nil.
    let firestoreProjectID: String?
    /// Firebase/GCP project ID for Cloud Logging access (for error logs), or nil.
    let gcpProjectID: String?
    /// The app name as it appears in AdMob (displayLabel). nil = no AdMob for this app.
    let admobAppName: String?
    let icon: String
    let tintColor: ProjectColor

    var hasAnalytics: Bool { ga4PropertyID != nil }
    var hasFirestore: Bool { firestoreProjectID != nil }

    enum ProjectColor: String {
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

    static let all: [FirebaseProject] = [
        FirebaseProject(
            id: "allApps",
            name: "All Apps",
            ga4PropertyID: "525369771",
            streamIDs: nil,
            firestoreProjectID: nil,
            gcpProjectID: "globalvibes-1a6aa",
            admobAppName: nil,
            icon: "square.grid.2x2.fill",
            tintColor: .orange
        ),
        FirebaseProject(
            id: "mauiTrolly",
            name: "Maui Trolly",
            ga4PropertyID: "525369771",
            streamIDs: ["13644174285", "13643159972", "13643192970"],
            firestoreProjectID: nil,
            gcpProjectID: "globalvibes-1a6aa",
            admobAppName: "Maui Trolly",
            icon: "tram.fill",
            tintColor: .blue
        ),
        FirebaseProject(
            id: "creoleTranslator",
            name: "Creole Translator",
            ga4PropertyID: "525369771",
            streamIDs: ["13651179226"],
            firestoreProjectID: nil,
            gcpProjectID: "globalvibes-1a6aa",
            admobAppName: "CreoleTranslator",
            icon: "character.bubble.fill",
            tintColor: .purple
        ),
        FirebaseProject(
            id: "resortBrowser",
            name: "Resort Browser",
            ga4PropertyID: "525769038",
            streamIDs: nil,
            firestoreProjectID: "resortviewer",
            gcpProjectID: "resortviewer",
            admobAppName: nil,
            icon: "beach.umbrella.fill",
            tintColor: .green
        ),
    ]
}
