import Foundation
import SwiftUI

/// Manages user-configured Firebase projects and their credentials.
/// Projects (non-sensitive) live in UserDefaults; service account JSON lives in Keychain.
@MainActor
final class CredentialStore: ObservableObject {

    // MARK: - Default AdMob OAuth client (gcloud installed-app — public, non-sensitive)
    static let defaultClientID     = "764086051850-6qr4p6gpi6hn506pt8ejuq83di341hur.apps.googleusercontent.com"
    static let defaultClientSecret = "d-FL95Q19q7MQmFpd7hHD0Ty"

    @Published var projects: [FirebaseProject] = []
    @Published var admobClientID:     String = defaultClientID
    @Published var admobClientSecret: String = defaultClientSecret
    /// GCP project ID used for AdMob quota billing (x-goog-user-project header).
    @Published var admobGCPProjectID: String = ""

    private let projectsKey          = "user_projects_v2"
    private let admobClientIDKey     = "user_admob_client_id"
    private let admobClientSecretKey = "user_admob_client_secret"
    private let admobGCPProjectKey   = "user_admob_gcp_project"

    init() { load() }

    // MARK: - Project management

    func addProject(_ project: FirebaseProject) {
        projects.append(project)
        save()
    }

    func updateProject(_ project: FirebaseProject) {
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx] = project
            save()
        }
    }

    func deleteProject(id: String) {
        projects.removeAll { $0.id == id }
        KeychainService.delete(saKey(id))
        KeychainService.delete(fsKey(id))
        save()
    }

    // MARK: - Service account access

    func serviceAccountJSON(for projectID: String) -> String? {
        KeychainService.load(saKey(projectID))
    }

    func setServiceAccount(json: String, for projectID: String) {
        KeychainService.save(saKey(projectID), value: json)
        // Auto-populate GCP project ID from SA if not set
        if admobGCPProjectID.isEmpty,
           let data = json.data(using: .utf8),
           let parsed = try? JSONDecoder().decode(SAProjectID.self, from: data) {
            admobGCPProjectID = parsed.project_id
            UserDefaults.standard.set(admobGCPProjectID, forKey: admobGCPProjectKey)
        }
    }

    func firestoreServiceAccountJSON(for projectID: String) -> String? {
        KeychainService.load(fsKey(projectID))
    }

    func setFirestoreServiceAccount(json: String, for projectID: String) {
        KeychainService.save(fsKey(projectID), value: json)
    }

    // MARK: - AdMob credentials

    func saveAdMobCredentials(clientID: String, clientSecret: String, gcpProjectID: String) {
        admobClientID     = clientID.isEmpty     ? Self.defaultClientID     : clientID
        admobClientSecret = clientSecret.isEmpty ? Self.defaultClientSecret : clientSecret
        admobGCPProjectID = gcpProjectID
        KeychainService.save(admobClientIDKey,     value: admobClientID)
        KeychainService.save(admobClientSecretKey, value: admobClientSecret)
        UserDefaults.standard.set(gcpProjectID, forKey: admobGCPProjectKey)
    }

    func resetAdMobCredentials() {
        admobClientID     = Self.defaultClientID
        admobClientSecret = Self.defaultClientSecret
        KeychainService.save(admobClientIDKey,     value: admobClientID)
        KeychainService.save(admobClientSecretKey, value: admobClientSecret)
    }

    // MARK: - Helpers

    var hasProjects: Bool { !projects.isEmpty }

    var allAppsProject: FirebaseProject {
        FirebaseProject(
            id: "allApps",
            name: "All Apps",
            ga4PropertyID: projects.compactMap(\.ga4PropertyID).first,
            streamIDs: nil,
            firestoreProjectID: nil,
            admobAppName: nil,
            icon: "square.grid.2x2.fill",
            tintColor: .orange
        )
    }

    var projectsWithAllApps: [FirebaseProject] {
        guard !projects.isEmpty else { return [] }
        return [allAppsProject] + projects
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(projects) {
            UserDefaults.standard.set(data, forKey: projectsKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: projectsKey),
           let decoded = try? JSONDecoder().decode([FirebaseProject].self, from: data) {
            projects = decoded
        }
        admobClientID     = KeychainService.load(admobClientIDKey)     ?? Self.defaultClientID
        admobClientSecret = KeychainService.load(admobClientSecretKey) ?? Self.defaultClientSecret
        admobGCPProjectID = UserDefaults.standard.string(forKey: admobGCPProjectKey) ?? ""
    }

    private func saKey(_ id: String) -> String  { "sa_json_\(id)" }
    private func fsKey(_ id: String) -> String  { "fs_sa_json_\(id)" }

    private struct SAProjectID: Decodable { let project_id: String }
}
