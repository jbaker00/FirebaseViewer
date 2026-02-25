import Foundation

@MainActor
final class AnalyticsService: ObservableObject {

    @Published var selectedProject: FirebaseProject = FirebaseProject.all[0]
    @Published var stats = DashboardStats()
    @Published var countryData: [CountryUserCount] = []
    @Published var appVersionStats: [AppVersionStats] = []
    @Published var firestoreStats: [FirestoreCollectionStats] = []
    @Published var isLoading = false
    @Published var error: String?

    // Separate cache per property (525369771 vs 525769038)
    private var tokenCache: [String: (token: String, expiry: Date)] = [:]

    // MARK: - Public

    func select(project: FirebaseProject) async {
        guard project != selectedProject else { return }
        selectedProject = project
        stats = DashboardStats()
        countryData = []
        appVersionStats = []
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
            async let fsTask = FirestoreService.fetchCollectionStats(projectID: firestoreProjectID)
            // GA4 analytics fetch
            if let propertyID = selectedProject.ga4PropertyID {
                let streamFilter = selectedProject.streamIDs.map { RunReportRequest.streamFilter(ids: $0) }
                do {
                    let token = try await getToken(forProperty: propertyID)
                    async let statsTask   = fetchStats(token: token, propertyID: propertyID, filter: streamFilter)
                    async let countryTask = fetchCountryData(token: token, propertyID: propertyID, filter: streamFilter)
                    async let versionTask = fetchAppVersionData(token: token, propertyID: propertyID, filter: streamFilter)
                    let (newStats, countries, versions, fs) = try await (statsTask, countryTask, versionTask, fsTask)
                    self.stats = newStats
                    self.countryData = countries
                    self.appVersionStats = versions
                    self.firestoreStats = fs
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
                let (newStats, countries, versions) = try await (statsTask, countryTask, versionTask)
                self.stats = newStats
                self.countryData = countries
                self.appVersionStats = versions
            } catch {
                self.error = error.localizedDescription
            }
        }
        // NJBusScheduler: no GA4, no Firestore — stats stay empty
    }

    // MARK: - Auth

    private func getToken(forProperty propertyID: String) async throws -> String {
        if let cached = tokenCache[propertyID], Date() < cached.expiry {
            return cached.token
        }
        let token = try await JWTService.accessToken()
        tokenCache[propertyID] = (token, Date().addingTimeInterval(3500))
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

