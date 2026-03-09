import SwiftUI

/// Settings screen — provides Google Sign-In as an alternative to bundled
/// service-account credentials, so the app works without `gcloud` or a
/// manually downloaded service-account JSON key.
struct SettingsView: View {
    @EnvironmentObject private var googleSignIn: GoogleSignInService
    @EnvironmentObject private var analytics: AnalyticsService

    var body: some View {
        NavigationStack {
            List {
                analyticsAuthSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Analytics Auth Section

    private var analyticsAuthSection: some View {
        Section {
            if googleSignIn.isSignedIn {
                signedInRow
            } else {
                signedOutRow
            }
            if let err = googleSignIn.error {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Analytics & Firebase APIs")
        } footer: {
            Text(googleSignIn.isSignedIn
                 ? "Your Google account is used to authenticate with GA4 Analytics, Firestore, and Cloud Logging — no service-account JSON key required."
                 : "Sign in with Google to access GA4 Analytics, Firestore, and Cloud Logging without a service-account key file or gcloud CLI.")
        }
    }

    private var signedInRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Signed in with Google")
                    .font(.headline)
                Text("OAuth 2.0 token active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                googleSignIn.signOut()
            } label: {
                Text("Sign Out")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    private var signedOutRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "person.badge.key.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not signed in")
                        .font(.headline)
                    Text("Using service-account credentials (if available)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                Task {
                    await googleSignIn.signIn()
                    if googleSignIn.isSignedIn {
                        // Reload analytics data with the new OAuth token.
                        await analytics.loadAll()
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "person.badge.key.fill")
                    Text("Sign in with Google")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.blue.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version") {
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Auth Method") {
                Text(googleSignIn.isSignedIn ? "Google Sign-In (OAuth 2.0)" : "Service Account JWT")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
