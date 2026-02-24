import Foundation

struct FirebaseProject: Identifiable, Equatable {
    let id: String          // unique key
    let name: String        // display name
    let ga4PropertyID: String?
    let icon: String        // SF Symbol
    let tintColor: ProjectColor

    enum ProjectColor: String {
        case orange, blue, green

        var swiftUIName: String { rawValue }
    }

    static let all: [FirebaseProject] = [
        FirebaseProject(
            id: "mauiTrolly",
            name: "Maui Trolly",
            ga4PropertyID: "525369771",
            icon: "tram.fill",
            tintColor: .orange
        ),
        FirebaseProject(
            id: "resortViewer",
            name: "Resort Viewer",
            ga4PropertyID: "525769038",
            icon: "binoculars.fill",
            tintColor: .blue
        ),
        FirebaseProject(
            id: "njBusScheduler",
            name: "NJ Bus Scheduler",
            ga4PropertyID: nil,
            icon: "bus.fill",
            tintColor: .green
        ),
    ]
}
