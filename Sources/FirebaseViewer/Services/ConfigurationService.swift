import Foundation
import SwiftUI

/// Manages user-provided configuration for Firebase/GCP projects.
/// All sensitive data is stored in Keychain; project metadata in UserDefaults.
@MainActor
final class ConfigurationService: ObservableObject {

    static let shared = ConfigurationService()

    @Published var projects: [FirebaseProject] = []
    @Published var isConfigured: Bool = false
    @Published var hasServiceAccount: Bool = false
    @Published var adMobClientID: String = ""

    private let saKeychainKey = "user_service_account_json"
    private let projectsDefaultsKey = "user_firebase_projects"
    private let admobClientIDKey = "user_admob_client_id"
    private let admobClientSecretKey = "user_admob_client_secret"

    init() {
        loadConfiguration()
    }

    // MARK: - Service Account

    func saveServiceAccount(json: String) {
        KeychainService.save(saKeychainKey, value: json)
        hasServiceAccount = true
        isConfigured = true
        AppLogger.log("Service account saved to Keychain", tag: "Config")
    }

    func loadServiceAccountJSON() -> String? {
        KeychainService.load(saKeychainKey)
    }

    func removeServiceAccount() {
        KeychainService.delete(saKeychainKey)
        hasServiceAccount = false
        isConfigured = !projects.isEmpty
        AppLogger.log("Service account removed", tag: "Config")
    }

    // MARK: - AdMob OAuth

    func saveAdMobCredentials(clientID: String, clientSecret: String) {
        KeychainService.save(admobClientIDKey, value: clientID)
        KeychainService.save(admobClientSecretKey, value: clientSecret)
        adMobClientID = clientID
        AppLogger.log("AdMob OAuth credentials saved", tag: "Config")
    }

    func loadAdMobClientID() -> String? {
        KeychainService.load(admobClientIDKey)
    }

    func loadAdMobClientSecret() -> String? {
        KeychainService.load(admobClientSecretKey)
    }

    // MARK: - Projects

    func addProject(_ project: FirebaseProject) {
        projects.append(project)
        saveProjects()
        isConfigured = true
    }

    func removeProject(id: String) {
        projects.removeAll { $0.id == id }
        saveProjects()
        isConfigured = hasServiceAccount || !projects.isEmpty
    }

    func updateProject(_ project: FirebaseProject) {
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx] = project
            saveProjects()
        }
    }

    // MARK: - Reset

    func resetAll() {
        KeychainService.delete(saKeychainKey)
        KeychainService.delete(admobClientIDKey)
        KeychainService.delete(admobClientSecretKey)
        KeychainService.delete("admob_refresh_token")
        UserDefaults.standard.removeObject(forKey: projectsDefaultsKey)
        projects = []
        hasServiceAccount = false
        isConfigured = false
        adMobClientID = ""
        AppLogger.log("All configuration reset", tag: "Config")
    }

    // MARK: - Persistence

    private func loadConfiguration() {
        hasServiceAccount = KeychainService.load(saKeychainKey) != nil
        adMobClientID = KeychainService.load(admobClientIDKey) ?? ""

        if let data = UserDefaults.standard.data(forKey: projectsDefaultsKey),
           let decoded = try? JSONDecoder().decode([StoredProject].self, from: data) {
            projects = decoded.map { $0.toFirebaseProject() }
        }

        isConfigured = hasServiceAccount || !projects.isEmpty
    }

    private func saveProjects() {
        let stored = projects.map { StoredProject(from: $0) }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: projectsDefaultsKey)
        }
    }
}

// MARK: - Codable wrapper for FirebaseProject

private struct StoredProject: Codable {
    let id: String
    let name: String
    let ga4PropertyID: String?
    let streamIDs: [String]?
    let firestoreProjectID: String?
    let gcpProjectID: String?
    let admobAppName: String?
    let icon: String
    let tintColor: String

    init(from project: FirebaseProject) {
        self.id = project.id
        self.name = project.name
        self.ga4PropertyID = project.ga4PropertyID
        self.streamIDs = project.streamIDs
        self.firestoreProjectID = project.firestoreProjectID
        self.gcpProjectID = project.gcpProjectID
        self.admobAppName = project.admobAppName
        self.icon = project.icon
        self.tintColor = project.tintColor.rawValue
    }

    func toFirebaseProject() -> FirebaseProject {
        FirebaseProject(
            id: id,
            name: name,
            ga4PropertyID: ga4PropertyID,
            streamIDs: streamIDs,
            firestoreProjectID: firestoreProjectID,
            gcpProjectID: gcpProjectID,
            admobAppName: admobAppName,
            icon: icon,
            tintColor: FirebaseProject.ProjectColor(rawValue: tintColor) ?? .blue
        )
    }
}
