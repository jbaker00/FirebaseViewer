import Foundation

/// Persists user-supplied service account credentials and custom Firebase projects.
final class UserProjectStore: ObservableObject {

    // MARK: - Storage keys

    static let saJSONKey             = "user_service_account_json"
    private static let customProjectsKey = "user_custom_firebase_projects"

    // MARK: - Published state

    @Published var serviceAccountJSON: String
    @Published var customProjects: [FirebaseProject]

    // MARK: - Init

    init() {
        serviceAccountJSON = KeychainService.load(Self.saJSONKey) ?? ""
        customProjects = Self.loadCustomProjects()
    }

    // MARK: - Service Account

    var hasCustomServiceAccount: Bool { !serviceAccountJSON.isEmpty }

    var hasBundledServiceAccount: Bool {
        Bundle.main.url(forResource: "ServiceAccount", withExtension: "json") != nil
    }

    func saveServiceAccount(_ json: String) {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainService.delete(Self.saJSONKey)
        } else {
            KeychainService.save(Self.saJSONKey, value: trimmed)
        }
        serviceAccountJSON = trimmed
    }

    // MARK: - Custom Projects

    var allProjects: [FirebaseProject] {
        FirebaseProject.all + customProjects
    }

    func addProject(_ project: FirebaseProject) {
        customProjects.append(project)
        saveCustomProjects()
    }

    func removeProject(at offsets: IndexSet) {
        customProjects.remove(atOffsets: offsets)
        saveCustomProjects()
    }

    // MARK: - Persistence

    private struct StoredProject: Codable {
        let id: String
        let name: String
        let ga4PropertyID: String?
        let streamIDs: [String]?
        let firestoreProjectID: String?
        let admobAppName: String?
        let icon: String
        let tintColor: String
    }

    private static func loadCustomProjects() -> [FirebaseProject] {
        guard let data = UserDefaults.standard.data(forKey: customProjectsKey),
              let stored = try? JSONDecoder().decode([StoredProject].self, from: data) else {
            return []
        }
        return stored.map { s in
            FirebaseProject(
                id: s.id,
                name: s.name,
                ga4PropertyID: s.ga4PropertyID,
                streamIDs: s.streamIDs,
                firestoreProjectID: s.firestoreProjectID,
                admobAppName: s.admobAppName,
                icon: s.icon,
                tintColor: FirebaseProject.ProjectColor(rawValue: s.tintColor) ?? .blue
            )
        }
    }

    private func saveCustomProjects() {
        let stored = customProjects.map { p in
            StoredProject(
                id: p.id,
                name: p.name,
                ga4PropertyID: p.ga4PropertyID,
                streamIDs: p.streamIDs,
                firestoreProjectID: p.firestoreProjectID,
                admobAppName: p.admobAppName,
                icon: p.icon,
                tintColor: p.tintColor.rawValue
            )
        }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.customProjectsKey)
        }
    }
}
