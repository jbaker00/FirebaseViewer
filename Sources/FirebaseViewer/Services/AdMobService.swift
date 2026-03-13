import Foundation
import AuthenticationServices
import SwiftUI

// MARK: - AdMob OAuth + API service

@MainActor
final class AdMobService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

    @Published var stats = AdMobStats()
    @Published var appStats: [AdMobAppStats] = []         // 30-day per-app
    @Published var todayEarnings: Double = 0
    @Published var todayAppStats: [AdMobAppStats] = []    // today per-app
    @Published var countryStats: [AdMobCountryStats] = [] // all-time per-country
    @Published var multiPeriodReports: [AdMobPeriodReport] = [] // Today/Yesterday/7d/30d
    @Published var allTimeEarnings: Double = 0            // all-time total earnings
    @Published var allTimeAppStats: [AdMobAppStats] = []  // all-time per-app breakdown
    @Published var paidOutAmount: Double = 0              // user-configured paid out amount
    @Published var isLoading = false
    @Published var hasData = false   // true once first successful load completes
    @Published var error: String?
    @Published var isAuthorized = false

    private let clientID     = "764086051850-6qr4p6gpi6hn506pt8ejuq83di341hur.apps.googleusercontent.com"
    private let clientSecret = "d-FL95Q19q7MQmFpd7hHD0Ty"
    private let redirectScheme = "com.googleusercontent.apps.764086051850-6qr4p6gpi6hn506pt8ejuq83di341hur"
    private let quotaProject = "globalvibes-1a6aa"

    private let tokenKey = "admob_refresh_token"
    private let paidOutKey = "admob_paid_out_amount"
    private var accessToken: String?
    private var tokenExpiry: Date = .distantPast

    // MARK: - Public

    override init() {
        super.init()
        // Restore saved refresh token
        if let data = KeychainService.loadData(tokenKey) {
            isAuthorized = true
            _ = data // token stored, will use on next fetch
        }
        // Restore saved paid out amount
        if let data = UserDefaults.standard.data(forKey: paidOutKey),
           let amount = try? JSONDecoder().decode(Double.self, from: data) {
            paidOutAmount = amount
        }
    }

    func signIn() async {
        let authURLString = "https://accounts.google.com/o/oauth2/auth" +
            "?response_type=code" +
            "&client_id=\(clientID)" +
            "&redirect_uri=\(redirectScheme):/oauth2redirect" +
            "&scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fadmob.readonly" +
            "&access_type=offline" +
            "&prompt=consent"

        guard let authURL = URL(string: authURLString) else { return }

        do {
            AppLogger.log("Starting AdMob OAuth flow", tag: "AdMob")
            let result = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(url: authURL,
                                                         callbackURLScheme: redirectScheme) { url, err in
                    if let err { cont.resume(throwing: err) }
                    else if let url { cont.resume(returning: url) }
                    else { cont.resume(throwing: NSError(domain: "AdMob", code: -1,
                                                          userInfo: [NSLocalizedDescriptionKey: "No callback URL"])) }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                session.start()
            }
            // Extract code from callback URL
            guard let components = URLComponents(url: result, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                error = "No authorization code in callback"
                AppLogger.error("No auth code in OAuth callback: \(result)", tag: "AdMob")
                return
            }
            AppLogger.log("Got OAuth code, exchanging for token", tag: "AdMob")
            try await exchangeCodeForToken(code: code)
            isAuthorized = true
            AppLogger.log("AdMob authorized successfully", tag: "AdMob")
            await loadStats()
        } catch {
            self.error = error.localizedDescription
            AppLogger.error("AdMob sign-in failed: \(error.localizedDescription)", tag: "AdMob")
        }
    }

    func signOut() {
        KeychainService.delete(tokenKey)
        isAuthorized = false
        accessToken = nil
        tokenExpiry = .distantPast
        stats = AdMobStats()
        appStats = []
        todayAppStats = []
        todayEarnings = 0
        countryStats = []
        allTimeEarnings = 0
        hasData = false
    }

    func updatePaidOutAmount(_ amount: Double) {
        paidOutAmount = amount
        if let encoded = try? JSONEncoder().encode(amount) {
            UserDefaults.standard.set(encoded, forKey: paidOutKey)
        }
        // Recalculate unpaid earnings
        stats.paidOut = paidOutAmount
        stats.unpaidEarnings = allTimeEarnings - paidOutAmount
    }

    func loadStats() async {
        guard isAuthorized, !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let token = try await getAccessToken()
            let accounts = try await fetchAccounts(token: token)
            guard let publisherID = accounts.first else {
                self.error = "No AdMob account found"
                return
            }
            let cal = Calendar(identifier: .gregorian)
            let now = Date()
            let todayStart     = cal.startOfDay(for: now)
            let yesterdayStart = cal.date(byAdding: .day, value: -1, to: todayStart)!
            let last7Start     = cal.date(byAdding: .day, value: -7,  to: todayStart)!
            let last30Start    = cal.date(byAdding: .day, value: -30, to: todayStart)!

            async let thirtyDayTask  = fetchEarnings(publisherID: publisherID, token: token, daysBack: 30)
            async let todayTask      = fetchEarnings(publisherID: publisherID, token: token, daysBack: 0)
            async let countryTask    = fetchCountryEarnings(publisherID: publisherID, token: token)
            async let allTimeTask    = fetchAllTimeEarnings(publisherID: publisherID, token: token)
            async let todayPeriod    = fetchPeriodReport(publisherID: publisherID, token: token,
                                                         label: "Today",
                                                         startDate: todayStart, endDate: now)
            async let yesterdayPeriod = fetchPeriodReport(publisherID: publisherID, token: token,
                                                          label: "Yesterday",
                                                          startDate: yesterdayStart, endDate: todayStart)
            async let last7Period    = fetchPeriodReport(publisherID: publisherID, token: token,
                                                         label: "Last 7 Days",
                                                         startDate: last7Start, endDate: now)
            async let last30Period   = fetchPeriodReport(publisherID: publisherID, token: token,
                                                         label: "Last 30 Days",
                                                         startDate: last30Start, endDate: now)

            let ((totalStats, perApp), (todayStats, todayPerApp), countries, (allTime, allTimePerApp),
                 p0, p1, p2, p3) = try await (thirtyDayTask, todayTask, countryTask, allTimeTask,
                                               todayPeriod, yesterdayPeriod, last7Period, last30Period)
            self.stats = totalStats
            self.appStats = perApp
            self.todayEarnings = todayStats.totalEarnings
            self.todayAppStats = todayPerApp
            self.countryStats = countries.sorted { $0.earnings > $1.earnings }
            self.multiPeriodReports = [p0, p1, p2, p3]
            self.allTimeEarnings = allTime.totalEarnings
            self.allTimeAppStats = allTimePerApp

            // Update paid out and unpaid earnings
            self.stats.paidOut = paidOutAmount
            self.stats.unpaidEarnings = allTimeEarnings - paidOutAmount

            self.hasData = true
            AppLogger.log("AdMob today earnings: $\(String(format: "%.4f", todayStats.totalEarnings))", tag: "AdMob")
            AppLogger.log("AdMob all-time earnings: $\(String(format: "%.2f", allTime.totalEarnings))", tag: "AdMob")
            AppLogger.log("AdMob country stats: \(countries.count) countries", tag: "AdMob")
        } catch {
            self.error = error.localizedDescription
            AppLogger.error("AdMob loadStats: \(error.localizedDescription)", tag: "AdMob")
        }
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            #if canImport(UIKit)
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow }) ?? UIWindow()
            #else
            NSApp.keyWindow ?? NSWindow()
            #endif
        }
    }

    // MARK: - Private

    private func exchangeCodeForToken(code: String) async throws {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "code=\(code)&client_id=\(clientID)&client_secret=\(clientSecret)&redirect_uri=\(redirectScheme):/oauth2redirect&grant_type=authorization_code"
        req.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: req)
        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int
        }
        let resp = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = resp.access_token
        tokenExpiry = Date().addingTimeInterval(Double(resp.expires_in) - 60)
        if let refresh = resp.refresh_token {
            KeychainService.save(tokenKey, value: refresh)
        }
    }

    private func getAccessToken() async throws -> String {
        if let t = accessToken, Date() < tokenExpiry { return t }
        guard let refreshData = KeychainService.loadData(tokenKey),
              let refreshToken = String(data: refreshData, encoding: .utf8) else {
            isAuthorized = false
            throw NSError(domain: "AdMob", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Not authorized. Please sign in."])
        }
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "refresh_token=\(refreshToken)&client_id=\(clientID)&client_secret=\(clientSecret)&grant_type=refresh_token"
        req.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: req)
        struct TokenResponse: Decodable { let access_token: String; let expires_in: Int }
        let resp = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = resp.access_token
        tokenExpiry = Date().addingTimeInterval(Double(resp.expires_in) - 60)
        return resp.access_token
    }

    // The GCP project where AdMob API is enabled (used for quota header)
    private func admobRequest(url: URL, token: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if !quotaProject.isEmpty {
            req.setValue(quotaProject, forHTTPHeaderField: "x-goog-user-project")
        }
        return req
    }

    private func fetchAccounts(token: String) async throws -> [String] {
        let url = URL(string: "https://admob.googleapis.com/v1/accounts")!
        let req = admobRequest(url: url, token: token)
        let (data, resp) = try await URLSession.shared.data(for: req)
        AppLogger.log("AdMob accounts response: HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)")
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            AppLogger.log("AdMob accounts error: \(body)")
            throw NSError(domain: "AdMob", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: body])
        }
        struct AccountsResp: Decodable {
            struct Account: Decodable { let name: String; let publisherId: String }
            let account: [Account]?
        }
        let parsed = try JSONDecoder().decode(AccountsResp.self, from: data)
        return parsed.account?.map { $0.name } ?? []
    }

    private func fetchEarnings(publisherID: String, token: String, daysBack: Int) async throws -> (AdMobStats, [AdMobAppStats]) {
        func dateComponents(_ date: Date) -> [String: Int] {
            let cal = Calendar.current
            return ["year": cal.component(.year, from: date),
                    "month": cal.component(.month, from: date),
                    "day": cal.component(.day, from: date)]
        }
        let today = Date()
        let start = daysBack == 0 ? today : Calendar.current.date(byAdding: .day, value: -daysBack, to: today)!
        let url = URL(string: "https://admob.googleapis.com/v1/\(publisherID)/networkReport:generate")!
        var req = admobRequest(url: url, token: token)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "reportSpec": [
                "dateRange": [
                    "startDate": dateComponents(start),
                    "endDate":   dateComponents(today)
                ],
                "dimensions": ["APP"],
                "metrics": ["ESTIMATED_EARNINGS", "IMPRESSIONS", "CLICKS"],
                "dimensionFilters": []
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, httpResp) = try await URLSession.shared.data(for: req)
        AppLogger.log("AdMob earnings response: HTTP \((httpResp as? HTTPURLResponse)?.statusCode ?? 0)")
        if let http = httpResp as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            AppLogger.error("AdMob earnings HTTP \(http.statusCode): \(body)", tag: "AdMob")
            throw NSError(domain: "AdMob", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: body])
        }

        // Log full raw response so we can inspect the exact structure
        let rawBody = String(data: data, encoding: .utf8) ?? ""
        AppLogger.log("AdMob raw response (\(daysBack)d): \(rawBody)", tag: "AdMob")

        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            AppLogger.error("AdMob: failed to parse response as JSON array. Raw: \(rawBody.prefix(300))", tag: "AdMob")
            throw NSError(domain: "AdMob", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Unexpected response format: \(rawBody.prefix(200))"])
        }

        AppLogger.log("AdMob parsed \(array.count) objects in response (daysBack=\(daysBack))", tag: "AdMob")

        var totalEarnings = 0.0, totalImpressions = 0, totalClicks = 0
        var perApp: [AdMobAppStats] = []

        for obj in array {
            guard let row = obj["row"] as? [String: Any] else { continue }

            let dims    = row["dimensionValues"] as? [String: Any]
            let metrics = row["metricValues"]    as? [String: Any]
            let appName = (dims?["APP"] as? [String: Any])?["displayLabel"] as? String ?? "Unknown App"

            // Log raw metric dict so we can see the exact field names and types
            if let m = metrics { AppLogger.log("AdMob metrics raw: \(m)", tag: "AdMob") }

            let earnings    = microsDollar(from: metrics, key: "ESTIMATED_EARNINGS")
            let impressions = intValue(from: metrics, key: "IMPRESSIONS")
            let clicks      = intValue(from: metrics, key: "CLICKS")

            totalEarnings    += earnings
            totalImpressions += impressions
            totalClicks      += clicks
            AppLogger.log("AdMob row[\(daysBack)d]: \(appName) $\(String(format:"%.6f",earnings)) imp=\(impressions)", tag: "AdMob")
            perApp.append(AdMobAppStats(appName: appName, earnings: earnings, impressions: impressions))
        }

        AppLogger.log("AdMob total[\(daysBack)d]: $\(String(format:"%.6f",totalEarnings)) imp=\(totalImpressions)", tag: "AdMob")
        var s = AdMobStats()
        s.totalEarnings = totalEarnings
        s.impressions   = totalImpressions
        s.clicks        = totalClicks
        s.ecpm = totalImpressions > 0 ? (totalEarnings / Double(totalImpressions)) * 1000 : 0
        return (s, perApp.sorted { $0.earnings > $1.earnings })
    }

    /// Extract a currency amount from a metric dict. Handles microsValue (String or Number)
    /// and doubleValue (String or Number) — AdMob varies by SDK version.
    private func microsDollar(from metrics: [String: Any]?, key: String) -> Double {
        guard let field = metrics?[key] as? [String: Any] else { return 0 }
        // microsValue — proto3 encodes int64 as string, but some versions return NSNumber
        if let s = field["microsValue"] as? String,   let v = Double(s)   { return v / 1_000_000 }
        if let n = field["microsValue"] as? NSNumber                        { return n.doubleValue / 1_000_000 }
        // doubleValue fallback
        if let s = field["doubleValue"] as? String,   let v = Double(s)   { return v }
        if let n = field["doubleValue"] as? NSNumber                        { return n.doubleValue }
        AppLogger.error("AdMob: cannot parse \(key) from \(field)", tag: "AdMob")
        return 0
    }

    private func intValue(from metrics: [String: Any]?, key: String) -> Int {
        guard let field = metrics?[key] as? [String: Any] else { return 0 }
        if let s = field["integerValue"] as? String,  let v = Int(s)      { return v }
        if let n = field["integerValue"] as? NSNumber                       { return n.intValue }
        return 0
    }

    // MARK: - Country earnings (all time: 2015-01-01 → today, broken down by app)

    private func fetchCountryEarnings(publisherID: String, token: String) async throws -> [AdMobCountryStats] {
        let today = Date()
        let cal = Calendar(identifier: .gregorian)
        let end = cal.dateComponents([.year, .month, .day], from: today)

        let url = URL(string: "https://admob.googleapis.com/v1/\(publisherID)/networkReport:generate")!
        var req = admobRequest(url: url, token: token)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "reportSpec": [
                "dateRange": [
                    "startDate": ["year": 2015, "month": 1, "day": 1],
                    "endDate":   ["year": end.year!, "month": end.month!, "day": end.day!]
                ],
                "dimensions": ["COUNTRY", "APP"],
                "metrics": ["ESTIMATED_EARNINGS", "IMPRESSIONS"],
                "localizationSettings": ["currencyCode": "USD"]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            AppLogger.error("AdMob country report error: \(body)", tag: "AdMob")
            return []
        }

        guard let objects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        let isoToName = CountryCoordinates.isoCodeTable

        // Group rows by country code
        struct RawRow { let appName: String; let earnings: Double; let impressions: Int }
        var grouped: [String: [RawRow]] = [:]

        for obj in objects {
            guard let row = obj["row"] as? [String: Any],
                  let dims = row["dimensionValues"] as? [String: Any],
                  let metrics = row["metricValues"] as? [String: Any] else { continue }

            let countryCode = (dims["COUNTRY"] as? [String: Any])?["value"] as? String ?? "ZZ"
            let appName     = (dims["APP"] as? [String: Any])?["displayLabel"] as? String ?? "Unknown"
            let earnings    = microsDollar(from: metrics, key: "ESTIMATED_EARNINGS")
            let impressions = intValue(from: metrics, key: "IMPRESSIONS")

            grouped[countryCode, default: []].append(RawRow(appName: appName, earnings: earnings, impressions: impressions))
        }

        var result: [AdMobCountryStats] = []
        for (code, rows) in grouped {
            let name        = isoToName[code] ?? code
            let total       = rows.reduce(0) { $0 + $1.earnings }
            let totalImp    = rows.reduce(0) { $0 + $1.impressions }
            let breakdown   = rows
                .sorted { $0.earnings > $1.earnings }
                .map { AdMobCountryStats.AppEntry(appName: $0.appName, earnings: $0.earnings, impressions: $0.impressions) }
            result.append(AdMobCountryStats(countryCode: code, countryName: name,
                                            earnings: total, impressions: totalImp,
                                            appBreakdown: breakdown))
        }
        AppLogger.log("AdMob country map: \(result.count) countries", tag: "AdMob")
        return result
    }

    // MARK: - All-time earnings (from 2015-01-01 to today, aggregated by app)

    private func fetchAllTimeEarnings(publisherID: String, token: String) async throws -> (AdMobStats, [AdMobAppStats]) {
        let today = Date()
        let cal = Calendar(identifier: .gregorian)
        let end = cal.dateComponents([.year, .month, .day], from: today)

        let url = URL(string: "https://admob.googleapis.com/v1/\(publisherID)/networkReport:generate")!
        var req = admobRequest(url: url, token: token)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "reportSpec": [
                "dateRange": [
                    "startDate": ["year": 2015, "month": 1, "day": 1],
                    "endDate":   ["year": end.year!, "month": end.month!, "day": end.day!]
                ],
                "dimensions": ["APP"],
                "metrics": ["ESTIMATED_EARNINGS", "IMPRESSIONS", "CLICKS"]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            AppLogger.error("AdMob all-time fetch failed", tag: "AdMob")
            return (AdMobStats(), [])
        }

        var totalEarnings = 0.0, totalImpressions = 0, totalClicks = 0
        var perApp: [AdMobAppStats] = []

        for obj in array {
            guard let row = obj["row"] as? [String: Any] else { continue }
            let dims    = row["dimensionValues"] as? [String: Any]
            let metrics = row["metricValues"]    as? [String: Any]
            let appName = (dims?["APP"] as? [String: Any])?["displayLabel"] as? String ?? "Unknown App"

            let earnings    = microsDollar(from: metrics, key: "ESTIMATED_EARNINGS")
            let impressions = intValue(from: metrics, key: "IMPRESSIONS")
            let clicks      = intValue(from: metrics, key: "CLICKS")

            totalEarnings    += earnings
            totalImpressions += impressions
            totalClicks      += clicks
            perApp.append(AdMobAppStats(appName: appName, earnings: earnings, impressions: impressions))
        }

        var s = AdMobStats()
        s.totalEarnings = totalEarnings
        s.impressions   = totalImpressions
        s.clicks        = totalClicks
        s.ecpm = totalImpressions > 0 ? (totalEarnings / Double(totalImpressions)) * 1000 : 0
        return (s, perApp.sorted { $0.earnings > $1.earnings })
    }

    // MARK: - Multi-period report (Today / Yesterday / Last 7 Days / Last 30 Days)

    private func fetchPeriodReport(
        publisherID: String,
        token: String,
        label: String,
        startDate: Date,
        endDate: Date
    ) async throws -> AdMobPeriodReport {
        let cal = Calendar(identifier: .gregorian)
        let startDC = cal.dateComponents([.year, .month, .day], from: startDate)
        let endDC   = cal.dateComponents([.year, .month, .day], from: endDate)

        let url = URL(string: "https://admob.googleapis.com/v1/\(publisherID)/networkReport:generate")!
        var req = admobRequest(url: url, token: token)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "reportSpec": [
                "dateRange": [
                    "startDate": ["year": startDC.year!, "month": startDC.month!, "day": startDC.day!],
                    "endDate":   ["year": endDC.year!,   "month": endDC.month!,   "day": endDC.day!]
                ],
                "dimensions": ["APP", "COUNTRY"],
                "metrics": ["ESTIMATED_EARNINGS", "IMPRESSIONS", "CLICKS", "AD_REQUESTS"],
                "localizationSettings": ["currencyCode": "USD"]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return AdMobPeriodReport(label: label, earnings: 0, impressions: 0, clicks: 0,
                                    adRequests: 0, appBreakdown: [], countryBreakdown: [])
        }

        let isoToName = CountryCoordinates.isoCodeTable

        struct RawRow {
            let appName: String
            let countryCode: String
            let countryName: String
            let earnings: Double
            let impressions: Int
            let clicks: Int
            let adRequests: Int
        }

        var rows: [RawRow] = []
        for obj in objects {
            guard let row  = obj["row"]             as? [String: Any],
                  let dims = row["dimensionValues"] as? [String: Any],
                  let mets = row["metricValues"]    as? [String: Any] else { continue }
            let appName     = (dims["APP"]     as? [String: Any])?["displayLabel"] as? String ?? "Unknown"
            let countryCode = (dims["COUNTRY"] as? [String: Any])?["value"]        as? String ?? "ZZ"
            let countryName = isoToName[countryCode] ?? countryCode
            rows.append(RawRow(
                appName: appName, countryCode: countryCode, countryName: countryName,
                earnings:    microsDollar(from: mets, key: "ESTIMATED_EARNINGS"),
                impressions: intValue(from: mets, key: "IMPRESSIONS"),
                clicks:      intValue(from: mets, key: "CLICKS"),
                adRequests:  intValue(from: mets, key: "AD_REQUESTS")
            ))
        }

        // Aggregate by app
        var appMap: [String: (Double, Int, Int, Int)] = [:]
        for r in rows {
            let cur = appMap[r.appName] ?? (0, 0, 0, 0)
            appMap[r.appName] = (cur.0 + r.earnings, cur.1 + r.impressions,
                                 cur.2 + r.clicks, cur.3 + r.adRequests)
        }

        // Aggregate by country
        var countryMap: [String: (name: String, earnings: Double, imp: Int, clicks: Int, req: Int)] = [:]
        for r in rows {
            let cur = countryMap[r.countryCode]
            countryMap[r.countryCode] = (
                name:     r.countryName,
                earnings: (cur?.earnings ?? 0) + r.earnings,
                imp:      (cur?.imp      ?? 0) + r.impressions,
                clicks:   (cur?.clicks   ?? 0) + r.clicks,
                req:      (cur?.req      ?? 0) + r.adRequests
            )
        }

        let appBreakdown = appMap.map { name, v in
            AdMobPeriodReport.AppRow(name: name, earnings: v.0, impressions: v.1, clicks: v.2)
        }.sorted { $0.earnings > $1.earnings }

        let countryBreakdown = countryMap.map { code, v in
            AdMobPeriodReport.CountryRow(code: code, name: v.name,
                                         earnings: v.earnings, impressions: v.imp, clicks: v.clicks)
        }.sorted { $0.earnings > $1.earnings }

        return AdMobPeriodReport(
            label:            label,
            earnings:         rows.reduce(0) { $0 + $1.earnings },
            impressions:      rows.reduce(0) { $0 + $1.impressions },
            clicks:           rows.reduce(0) { $0 + $1.clicks },
            adRequests:       rows.reduce(0) { $0 + $1.adRequests },
            appBreakdown:     appBreakdown,
            countryBreakdown: countryBreakdown
        )
    }
}
