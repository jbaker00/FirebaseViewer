import Foundation

@MainActor
final class AnalyticsService: ObservableObject {

    @Published var selectedProject: FirebaseProject
    @Published var stats = DashboardStats()
    @Published var countryData: [CountryUserCount] = []
    @Published var appVersionStats: [AppVersionStats] = []
    @Published var versionCountryStats: [VersionCountryStats] = []
    @Published var firestoreStats: [FirestoreCollectionStats] = []
    @Published var ttsQuotaStats = TTSQuotaStats()
    @Published var isLoading = false
    @Published var error: String?

    // Separate cache per property
    private var tokenCache: [String: (token: String, expiry: Date)] = [:]
    /// Seconds before a token is considered expired and re-fetched.
    private let tokenExpiryBuffer: TimeInterval = 3500

    /// Injected Google Sign-In service. When the user is signed in this takes
    /// priority over the bundled service-account JSON, eliminating the need for
    /// `gcloud` or a service-account key file.
    private let googleSignIn: GoogleSignInService?

    init(googleSignIn: GoogleSignInService? = nil) {
        self.selectedProject = FirebaseProject.all[0]
        self.googleSignIn = googleSignIn
    }

    // MARK: - Public

    func select(project: FirebaseProject) async {
        guard project != selectedProject else { return }
        selectedProject = project
        stats = DashboardStats()
        countryData = []
        appVersionStats = []
        versionCountryStats = []
        firestoreStats = []
        error = nil
        await loadAll()
    }

    func loadAll() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        // Firestore fetch (ResortViewer only)
        if let firestoreProjectID = selectedProject.firestoreProjectID {
            let fsToken = try? await googleToken()
            async let fsTask = FirestoreService.fetchCollectionStats(projectID: firestoreProjectID, accessToken: fsToken)
            // GA4 analytics fetch
            if let propertyID = selectedProject.ga4PropertyID {
                let streamFilter = selectedProject.streamIDs.map { RunReportRequest.streamFilter(ids: $0) }
                do {
                    let token = try await getToken(forProperty: propertyID)
                    async let statsTask   = fetchStats(token: token, propertyID: propertyID, filter: streamFilter)
                    async let countryTask = fetchCountryData(token: token, propertyID: propertyID, filter: streamFilter)
                    async let versionTask = fetchAppVersionData(token: token, propertyID: propertyID, filter: streamFilter)
                    async let versionCountryTask = fetchVersionCountryData(token: token, propertyID: propertyID, filter: streamFilter)
                    let (newStats, countries, versions, versionCountries, fs) = try await (statsTask, countryTask, versionTask, versionCountryTask, fsTask)
                    self.stats = newStats
                    self.countryData = countries
                    self.appVersionStats = versions
                    self.versionCountryStats = versionCountries
                    self.firestoreStats = fs
                } catch let err as NSError where err.code == 403 {
                    // SA not yet granted access to this GA4 property
                    AppLogger.error("GA4 403 for property \(propertyID) — grant SA viewer access in GA4 console", tag: "GA4")
                    self.error = "Permission denied for GA4 property \(propertyID). Grant your service account Viewer access in the GA4 console."
                    if let fs = try? await fsTask { self.firestoreStats = fs }
                } catch {
                    self.error = error.localizedDescription
                    if let fs = try? await fsTask { self.firestoreStats = fs }
                }
            } else {
                if let fs = try? await fsTask { self.firestoreStats = fs }
            }
        } else if let propertyID = selectedProject.ga4PropertyID {
            let streamFilter = selectedProject.streamIDs.map { RunReportRequest.streamFilter(ids: $0) }
            do {
                let token = try await getToken(forProperty: propertyID)
                async let statsTask   = fetchStats(token: token, propertyID: propertyID, filter: streamFilter)
                async let countryTask = fetchCountryData(token: token, propertyID: propertyID, filter: streamFilter)
                async let versionTask = fetchAppVersionData(token: token, propertyID: propertyID, filter: streamFilter)
                async let versionCountryTask = fetchVersionCountryData(token: token, propertyID: propertyID, filter: streamFilter)
                let (newStats, countries, versions, versionCountries) = try await (statsTask, countryTask, versionTask, versionCountryTask)
                self.stats = newStats
                self.countryData = countries
                self.appVersionStats = versions
                self.versionCountryStats = versionCountries
            } catch let err as NSError where err.code == 403 {
                AppLogger.error("GA4 403 for property \(propertyID) — check SA permissions", tag: "GA4")
                self.error = "Permission denied for GA4 property \(propertyID). Grant your service account Viewer access in the GA4 console."
            } catch {
                self.error = error.localizedDescription
            }
        }
        // NJBusScheduler: no GA4, no Firestore — stats stay empty

        // Always fetch TTS quota stats for Creole Translator regardless of selected project
        await fetchAndUpdateTTSQuotaStats()
    }

    // MARK: - Auth

    /// Returns a Google Sign-In access token when the user is signed in, or nil otherwise.
    private func googleToken() async throws -> String? {
        guard let googleSignIn, googleSignIn.isSignedIn else { return nil }
        return try await googleSignIn.getAccessToken()
    }

    private func getToken(forProperty propertyID: String) async throws -> String {
        // Prefer Google Sign-In OAuth token when the user is signed in.
        if let googleSignIn, googleSignIn.isSignedIn {
            do {
                let token = try await googleSignIn.getAccessToken()
                tokenCache[propertyID] = (token, Date().addingTimeInterval(tokenExpiryBuffer))
                return token
            } catch {
                AppLogger.error("Google Sign-In token fetch failed, falling back to SA: \(error.localizedDescription)", tag: "GA4")
            }
        }
        // Fall back to the bundled service-account JWT (legacy / developer use).
        if let cached = tokenCache[propertyID], Date() < cached.expiry {
            return cached.token
        }
        let token = try await JWTService.accessToken()
        tokenCache[propertyID] = (token, Date().addingTimeInterval(tokenExpiryBuffer))
        return token
    }

    // MARK: - Fetch stats

    private func fetchStats(token: String, propertyID: String, filter: RunReportRequest.DimensionFilter?) async throws -> DashboardStats {
        let request = RunReportRequest(
            dateRanges: [.init(startDate: "30daysAgo", endDate: "today")],
            dimensions: [],
            metrics: [
                .init(name: "activeUsers"),
                .init(name: "newUsers"),
                .init(name: "sessions"),
                .init(name: "eventCount"),
                .init(name: "screenPageViews")
            ],
            limit: 1,
            dimensionFilter: filter
        )
        let response = try await runReport(request: request, token: token, propertyID: propertyID)
        var s = DashboardStats()
        if let row = response.rows?.first {
            let vals = row.metricValues.map { Int($0.value) ?? 0 }
            if vals.count >= 5 {
                s.activeUsers = vals[0]
                s.newUsers    = vals[1]
                s.sessions    = vals[2]
                s.eventCount  = vals[3]
                s.screenViews = vals[4]
            }
        }
        return s
    }

    // MARK: - Fetch per-app-version breakdown

    private func fetchAppVersionData(token: String, propertyID: String, filter: RunReportRequest.DimensionFilter?) async throws -> [AppVersionStats] {
        let request = RunReportRequest(
            dateRanges: [.init(startDate: "30daysAgo", endDate: "today")],
            dimensions: [.init(name: "appVersion"), .init(name: "operatingSystemVersion")],
            metrics: [
                .init(name: "activeUsers"),
                .init(name: "sessions"),
                .init(name: "eventCount"),
                .init(name: "crashAffectedUsers")
            ],
            limit: 50,
            dimensionFilter: filter
        )
        let response = try await runReport(request: request, token: token, propertyID: propertyID)
        return (response.rows ?? []).compactMap { row in
            let dims = row.dimensionValues ?? []
            let vals = row.metricValues.map { Int($0.value) ?? 0 }
            guard dims.count >= 2, vals.count >= 4 else { return nil }
            return AppVersionStats(
                version: dims[0].value,
                osVersion: dims[1].value,
                activeUsers: vals[0],
                sessions: vals[1],
                eventCount: vals[2],
                crashes: vals[3]
            )
        }
        .sorted { $0.activeUsers > $1.activeUsers }
    }

    // MARK: - Fetch user counts by country

    private func fetchCountryData(token: String, propertyID: String, filter: RunReportRequest.DimensionFilter?) async throws -> [CountryUserCount] {
        let request = RunReportRequest(
            dateRanges: [.init(startDate: "30daysAgo", endDate: "today")],
            dimensions: [.init(name: "country")],
            metrics: [.init(name: "activeUsers")],
            limit: 100,
            dimensionFilter: filter
        )
        let response = try await runReport(request: request, token: token, propertyID: propertyID)
        return (response.rows ?? []).compactMap { row in
            let country = row.dimensionValues?.first?.value ?? "(not set)"
            let users   = Int(row.metricValues.first?.value ?? "0") ?? 0
            guard users > 0, country != "(not set)" else { return nil }
            return CountryUserCount(
                country: country,
                userCount: users,
                coordinate: CountryCoordinates.coordinate(for: country)
            )
        }
        .sorted { $0.userCount > $1.userCount }
    }

    // MARK: - Fetch version × country breakdown

    private func fetchVersionCountryData(token: String, propertyID: String, filter: RunReportRequest.DimensionFilter?) async throws -> [VersionCountryStats] {
        let request = RunReportRequest(
            dateRanges: [.init(startDate: "30daysAgo", endDate: "today")],
            dimensions: [.init(name: "appVersion"), .init(name: "country")],
            metrics: [.init(name: "activeUsers")],
            limit: 200,
            dimensionFilter: filter
        )
        let response = try await runReport(request: request, token: token, propertyID: propertyID)
        return (response.rows ?? []).compactMap { row in
            let dims = row.dimensionValues ?? []
            let users = Int(row.metricValues.first?.value ?? "0") ?? 0
            guard dims.count >= 2, users > 0 else { return nil }
            let version = dims[0].value
            let country = dims[1].value
            guard country != "(not set)" else { return nil }
            return VersionCountryStats(version: version, country: country, activeUsers: users)
        }
        .sorted { $0.activeUsers > $1.activeUsers }
    }

    // MARK: - TTS quota stats

    private func fetchAndUpdateTTSQuotaStats() async {
        guard let project = FirebaseProject.all.first(where: { $0.id == "creoleTranslator" }),
              let propertyID = project.ga4PropertyID else { return }
        do {
            let token = try await getToken(forProperty: propertyID)
            ttsQuotaStats = try await fetchTTSQuotaStats(token: token, propertyID: propertyID)
        } catch {
            AppLogger.error("TTS quota stats fetch failed: \(error.localizedDescription)", tag: "GA4")
        }
    }

    private func fetchTTSQuotaStats(token: String, propertyID: String) async throws -> TTSQuotaStats {
        let request = RunReportRequest(
            dateRanges: [.init(startDate: "30daysAgo", endDate: "today")],
            dimensions: [.init(name: "eventName")],
            metrics: [.init(name: "eventCount")],
            limit: 10,
            dimensionFilter: RunReportRequest.eventFilter(names: [
                "openai_tts_quota_exceeded",
                "tts_fallback_to_computer"
            ])
        )
        let response = try await runReport(request: request, token: token, propertyID: propertyID)
        var stats = TTSQuotaStats()
        for row in response.rows ?? [] {
            let eventName = row.dimensionValues?.first?.value ?? ""
            let count = Int(row.metricValues.first?.value ?? "0") ?? 0
            switch eventName {
            case "openai_tts_quota_exceeded": stats.openAIQuotaExceededCount = count
            case "tts_fallback_to_computer":  stats.fallbackToComputerCount  = count
            default: break
            }
        }
        AppLogger.log(
            "TTS quota stats: openaiQuota=\(stats.openAIQuotaExceededCount) fallback=\(stats.fallbackToComputerCount)",
            tag: "GA4"
        )
        return stats
    }

    // MARK: - API call

    private func runReport(request: RunReportRequest, token: String, propertyID: String) async throws -> RunReportResponse {
        let urlString = "https://analyticsdata.googleapis.com/v1beta/properties/\(propertyID):runReport"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            AppLogger.error("GA4 HTTP \(httpResponse.statusCode): \(body)", tag: "GA4")
            throw NSError(domain: "GA4API", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(body)"])
        }
        AppLogger.log("GA4 runReport OK (property: \(propertyID))", tag: "GA4")

        return try JSONDecoder().decode(RunReportResponse.self, from: data)
    }
}

