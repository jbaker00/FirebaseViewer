import Foundation

struct FirebaseProject: Identifiable, Equatable {
    let id: String
    let name: String
    let ga4PropertyID: String
    /// One or more stream IDs to filter by. nil = all streams (no filter).
    let streamIDs: [String]?
    let icon: String
    let tintColor: ProjectColor

    enum ProjectColor: String {
        case orange, blue, purple

        var swiftUIName: String { rawValue }
    }

    static let all: [FirebaseProject] = [
        FirebaseProject(
            id: "allApps",
            name: "All Apps",
            ga4PropertyID: "525369771",
            streamIDs: nil,
            icon: "square.grid.2x2.fill",
            tintColor: .orange
        ),
        FirebaseProject(
            id: "mauiTrolly",
            name: "Maui Trolly",
            ga4PropertyID: "525369771",
            // All three MauiTrolly stream registrations
            streamIDs: ["13644174285", "13643159972", "13643192970"],
            icon: "tram.fill",
            tintColor: .blue
        ),
        FirebaseProject(
            id: "creoleTranslator",
            name: "Creole Translator",
            ga4PropertyID: "525369771",
            streamIDs: ["13651179226"],
            icon: "character.bubble.fill",
            tintColor: .purple
        ),
    ]
}
