import Foundation
import AuthenticationServices
import SwiftUI

// MARK: - AdMob OAuth + API service

@MainActor
final class AdMobService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

    @Published var stats = AdMobStats()
    @Published var appStats: [AdMobAppStats] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var isAuthorized = false

    // gcloud installed-app client (supports admob.readonly for project owners)
    private let clientID = "764086051850-6qr4p6gpi6hn506pt8ejuq83di341hur.apps.googleusercontent.com"
    private let clientSecret = "d-FL95Q19q7MQmFpd7hHD0Ty"
    private let redirectScheme = "com.googleusercontent.apps.764086051850-6qr4p6gpi6hn506pt8ejuq83di341hur"

    private let tokenKey = "admob_refresh_token"
    private var accessToken: String?
    private var tokenExpiry: Date = .distantPast

    // MARK: - Public

    override init() {
        super.init()
        // Restore saved refresh token
        if let data = KeychainHelper.read(key: tokenKey) {
            isAuthorized = true
            _ = data // token stored, will use on next fetch
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
        KeychainHelper.delete(key: tokenKey)
        isAuthorized = false
        accessToken = nil
        tokenExpiry = .distantPast
        stats = AdMobStats()
        appStats = []
    }

    func loadStats() async {
        guard isAuthorized else { return }
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
            let (totalStats, perApp) = try await fetchEarnings(publisherID: publisherID, token: token)
            self.stats = totalStats
            self.appStats = perApp
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow }) ?? UIWindow()
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
            KeychainHelper.save(key: tokenKey, value: refresh)
        }
    }

    private func getAccessToken() async throws -> String {
        if let t = accessToken, Date() < tokenExpiry { return t }
        guard let refreshData = KeychainHelper.read(key: tokenKey),
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

    // The user's GCP project where AdMob API is enabled
    private let quotaProject = "globalvibes-1a6aa"

    private func admobRequest(url: URL, token: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(quotaProject, forHTTPHeaderField: "x-goog-user-project")
        return req
    }

    private func fetchAccounts(token: String) async throws -> [String] {
        let url = URL(string: "https://admob.googleapis.com/v1/accounts")!
        var req = admobRequest(url: url, token: token)
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

    private func fetchEarnings(publisherID: String, token: String) async throws -> (AdMobStats, [AdMobAppStats]) {
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let thirtyDaysAgo = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-30*24*3600)).prefix(10)
        let url = URL(string: "https://admob.googleapis.com/v1/\(publisherID)/networkReport:generate")!
        var req = admobRequest(url: url, token: token)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "reportSpec": [
                "dateRange": [
                    "startDate": ["year": Int(thirtyDaysAgo.prefix(4))!, "month": Int(thirtyDaysAgo.dropFirst(5).prefix(2))!, "day": Int(thirtyDaysAgo.dropFirst(8))!],
                    "endDate":   ["year": Int(today.prefix(4))!,         "month": Int(today.dropFirst(5).prefix(2))!,         "day": Int(today.dropFirst(8))!]
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
            AppLogger.log("AdMob earnings error: \(body)")
            throw NSError(domain: "AdMob", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: body])
        }

        // Response is newline-delimited JSON (streaming)
        let lines = String(data: data, encoding: .utf8)?.components(separatedBy: "\n") ?? []
        var totalEarnings = 0.0, totalImpressions = 0, totalClicks = 0
        var perApp: [AdMobAppStats] = []

        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let row = obj["row"] as? [String: Any] else { continue }

            let dims = row["dimensionValues"] as? [String: Any]
            let metrics = row["metricValues"] as? [String: Any]
            let appName = (dims?["APP"] as? [String: Any])?["displayLabel"] as? String ?? "Unknown App"

            let earnings = Double((metrics?["ESTIMATED_EARNINGS"] as? [String: Any])?["microsValue"] as? String ?? "0") ?? 0
            let impressions = Int((metrics?["IMPRESSIONS"] as? [String: Any])?["integerValue"] as? String ?? "0") ?? 0
            let clicks = Int((metrics?["CLICKS"] as? [String: Any])?["integerValue"] as? String ?? "0") ?? 0

            totalEarnings += earnings / 1_000_000 // microseconds to dollars
            totalImpressions += impressions
            totalClicks += clicks
            perApp.append(AdMobAppStats(appName: appName, earnings: earnings/1_000_000, impressions: impressions))
        }

        var s = AdMobStats()
        s.totalEarnings = totalEarnings
        s.impressions = totalImpressions
        s.clicks = totalClicks
        s.ecpm = totalImpressions > 0 ? (totalEarnings / Double(totalImpressions)) * 1000 : 0
        return (s, perApp.sorted { $0.earnings > $1.earnings })
    }
}

// MARK: - Keychain helper

private enum KeychainHelper {
    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    static func read(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        return result as? Data
    }
    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
