import Foundation

// MARK: - Error Logs Service (Cloud Logging API)

@MainActor
final class ErrorLogsService: ObservableObject {

    @Published var entries: [ErrorLogEntry] = []
    @Published var isLoading = false
    @Published var hasData = false
    @Published var error: String?

    private let projects = FirebaseProject.all.filter { $0.id != "allApps" && $0.gcpProjectID != nil }

    /// Injected Google Sign-In service. When the user is signed in this takes
    /// priority over the bundled service-account JSON.
    private let googleSignIn: GoogleSignInService?

    init(googleSignIn: GoogleSignInService? = nil) {
        self.googleSignIn = googleSignIn
    }

    /// Fetch error logs from Cloud Logging API for all Firebase projects
    func loadErrorLogs(daysBack: Int = 7, groqOnly: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let token: String
            if let googleSignIn, googleSignIn.isSignedIn,
               let oauthToken = try? await googleSignIn.getAccessToken() {
                token = oauthToken
                AppLogger.log("Using Google Sign-In token for Cloud Logging", tag: "ErrorLogs")
            } else {
                token = try await JWTService.accessToken(
                    resource: "ServiceAccount",
                    scope: "https://www.googleapis.com/auth/logging.read"
                )
            }

            var allEntries: [ErrorLogEntry] = []

            // Fetch logs for each project in parallel
            await withTaskGroup(of: [ErrorLogEntry].self) { group in
                for project in projects {
                    if let projectID = project.gcpProjectID {
                        group.addTask {
                            await self.fetchLogsForProject(
                                projectID: projectID,
                                token: token,
                                daysBack: daysBack,
                                groqOnly: groqOnly
                            )
                        }
                    }
                }

                for await projectEntries in group {
                    allEntries.append(contentsOf: projectEntries)
                }
            }

            // Sort by timestamp descending (newest first)
            self.entries = allEntries.sorted { $0.timestamp > $1.timestamp }
            self.hasData = true

            AppLogger.log("Loaded \(allEntries.count) error log entries from Cloud Logging", tag: "ErrorLogs")
        } catch {
            self.error = error.localizedDescription
            AppLogger.error("Failed to load error logs: \(error.localizedDescription)", tag: "ErrorLogs")
        }
    }

    // MARK: - Private

    private func fetchLogsForProject(
        projectID: String,
        token: String,
        daysBack: Int,
        groqOnly: Bool
    ) async -> [ErrorLogEntry] {
        let url = URL(string: "https://logging.googleapis.com/v2/entries:list")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Calculate time range
        let now = Date()
        let startTime = Calendar.current.date(byAdding: .day, value: -daysBack, to: now)!
        let startISO = ISO8601DateFormatter().string(from: startTime)

        // Build filter
        var filter = "severity>=ERROR AND timestamp>=\"\(startISO)\""

        // Add resource filters for common Firebase/GCP services
        filter += " AND ("
        filter += "resource.type=\"cloud_function\" OR "
        filter += "resource.type=\"cloud_run_revision\" OR "
        filter += "resource.type=\"gae_app\" OR "
        filter += "resource.type=\"k8s_container\""
        filter += ")"

        // Filter for Groq-specific errors if requested
        if groqOnly {
            filter += " AND (textPayload=~\"(?i)groq\" OR jsonPayload.message=~\"(?i)groq\")"
        }

        let body: [String: Any] = [
            "resourceNames": ["projects/\(projectID)"],
            "filter": filter,
            "orderBy": "timestamp desc",
            "pageSize": 100
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            AppLogger.error("Failed to encode request body for project \(projectID)", tag: "ErrorLogs")
            return []
        }

        req.httpBody = bodyData

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)

            if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                let body = String(data: data, encoding: .utf8) ?? ""
                AppLogger.error("Cloud Logging HTTP \(http.statusCode) for \(projectID): \(body)", tag: "ErrorLogs")
                return []
            }

            let response = try JSONDecoder().decode(LogEntriesResponse.self, from: data)
            let entries = response.entries?.compactMap { $0.toErrorLogEntry() } ?? []

            AppLogger.log("Fetched \(entries.count) error logs from \(projectID)", tag: "ErrorLogs")
            return entries
        } catch {
            AppLogger.error("Error fetching logs from \(projectID): \(error.localizedDescription)", tag: "ErrorLogs")
            return []
        }
    }
}
