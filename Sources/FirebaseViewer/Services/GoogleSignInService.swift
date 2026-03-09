import Foundation
import AuthenticationServices
import SwiftUI

// MARK: - Google OAuth 2.0 sign-in for GA4 / Firestore / Cloud Logging

/// Manages Google Sign-In via OAuth 2.0 so the app can access GA4 Analytics,
/// Firestore, and Cloud Logging APIs without requiring a service-account JSON
/// key file or the `gcloud` CLI.
///
/// Uses the same Google OAuth 2.0 client already registered for AdMob.
/// The access token obtained here carries the scopes:
///   • `analytics.readonly`  – GA4 Data API
///   • `datastore`            – Cloud Firestore REST API
///   • `logging.read`         – Cloud Logging API
@MainActor
final class GoogleSignInService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

    @Published var isSignedIn = false
    @Published var error: String?

    // Reuse the same Google OAuth 2.0 installed-app client registered for AdMob.
    private let clientID     = "764086051850-6qr4p6gpi6hn506pt8ejuq83di341hur.apps.googleusercontent.com"
    private let clientSecret = "d-FL95Q19q7MQmFpd7hHD0Ty"
    private let redirectScheme = "com.googleusercontent.apps.764086051850-6qr4p6gpi6hn506pt8ejuq83di341hur"

    private let refreshTokenKey = "google_analytics_refresh_token"
    private var accessToken: String?
    private var tokenExpiry: Date = .distantPast

    // Combined scopes required by AnalyticsService, FirestoreService, and ErrorLogsService.
    private let scopes = [
        "https://www.googleapis.com/auth/analytics.readonly",
        "https://www.googleapis.com/auth/datastore",
        "https://www.googleapis.com/auth/logging.read"
    ].joined(separator: " ")

    override init() {
        super.init()
        isSignedIn = KeychainService.load(refreshTokenKey) != nil
    }

    // MARK: - Sign In / Out

    func signIn() async {
        let encodedScopes = scopes.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? scopes
        let authURLString = "https://accounts.google.com/o/oauth2/auth"
            + "?response_type=code"
            + "&client_id=\(clientID)"
            + "&redirect_uri=\(redirectScheme):/oauth2redirect"
            + "&scope=\(encodedScopes)"
            + "&access_type=offline"
            + "&prompt=consent"

        guard let authURL = URL(string: authURLString) else { return }

        do {
            AppLogger.log("Starting Google Sign-In OAuth flow", tag: "GoogleSignIn")
            let callbackURL = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(
                    url: authURL,
                    callbackURLScheme: redirectScheme
                ) { url, err in
                    if let err {
                        cont.resume(throwing: err)
                    } else if let url {
                        cont.resume(returning: url)
                    } else {
                        cont.resume(throwing: GoogleSignInError.noCallbackURL)
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                session.start()
            }

            guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                error = "No authorization code returned."
                AppLogger.error("No auth code in OAuth callback: \(callbackURL)", tag: "GoogleSignIn")
                return
            }

            try await exchangeCodeForToken(code: code)
            isSignedIn = true
            error = nil
            AppLogger.log("Google Sign-In successful", tag: "GoogleSignIn")
        } catch {
            self.error = error.localizedDescription
            AppLogger.error("Google Sign-In failed: \(error.localizedDescription)", tag: "GoogleSignIn")
        }
    }

    func signOut() {
        KeychainService.delete(refreshTokenKey)
        accessToken = nil
        tokenExpiry = .distantPast
        isSignedIn = false
        error = nil
        AppLogger.log("Google Sign-Out complete", tag: "GoogleSignIn")
    }

    // MARK: - Token Access

    /// Returns a valid access token, refreshing it automatically when expired.
    func getAccessToken() async throws -> String {
        if let token = accessToken, Date() < tokenExpiry {
            return token
        }
        guard let refreshToken = KeychainService.load(refreshTokenKey) else {
            throw GoogleSignInError.notSignedIn
        }
        return try await refreshAccessToken(refreshToken: refreshToken)
    }

    // MARK: - Private

    private func exchangeCodeForToken(code: String) async throws {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "code=\(code)"
            + "&client_id=\(clientID)"
            + "&client_secret=\(clientSecret)"
            + "&redirect_uri=\(redirectScheme):/oauth2redirect"
            + "&grant_type=authorization_code"
        req.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: req)
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)

        accessToken = response.access_token
        tokenExpiry = Date().addingTimeInterval(Double(response.expires_in ?? 3600) - 60)
        if let refresh = response.refresh_token {
            KeychainService.save(refreshTokenKey, value: refresh)
        }
    }

    private func refreshAccessToken(refreshToken: String) async throws -> String {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "refresh_token=\(refreshToken)"
            + "&client_id=\(clientID)"
            + "&client_secret=\(clientSecret)"
            + "&grant_type=refresh_token"
        req.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            if http.statusCode == 400 || http.statusCode == 401 {
                // Refresh token expired or revoked — require re-sign-in.
                signOut()
                throw GoogleSignInError.tokenExpired
            }
            throw GoogleSignInError.tokenRefreshFailed("HTTP \(http.statusCode): \(body)")
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        let newToken = tokenResponse.access_token
        accessToken = newToken
        tokenExpiry = Date().addingTimeInterval(Double(tokenResponse.expires_in ?? 3600) - 60)
        AppLogger.log("Google access token refreshed", tag: "GoogleSignIn")
        return newToken
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

    // MARK: - Models

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int?
    }
}

// MARK: - Errors

enum GoogleSignInError: LocalizedError {
    case notSignedIn
    case noCallbackURL
    case tokenExpired
    case tokenRefreshFailed(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in to Google. Tap \"Sign in with Google\" to authenticate."
        case .noCallbackURL:
            return "Sign-in was cancelled or returned no callback URL."
        case .tokenExpired:
            return "Your session has expired. Please sign in again."
        case .tokenRefreshFailed(let msg):
            return "Token refresh failed: \(msg)"
        }
    }
}
