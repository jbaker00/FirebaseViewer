import SwiftUI

/// Shown on first launch when no projects are configured.
struct OnboardingView: View {
    @EnvironmentObject private var credentialStore: CredentialStore
    @State private var showAddProject = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    Spacer(minLength: 40)

                    // Hero
                    VStack(spacing: 16) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(
                                LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom)
                            )

                        Text("Firebase Viewer")
                            .font(.largeTitle.bold())

                        Text("View your Firebase Analytics, AdMob revenue, and Firestore data — all in one place.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // Feature cards
                    VStack(spacing: 12) {
                        featureRow(icon: "chart.bar.fill", color: .blue,
                                   title: "Analytics", desc: "Active users, sessions, country maps")
                        featureRow(icon: "dollarsign.circle.fill", color: .green,
                                   title: "AdMob Revenue", desc: "Today's earnings, 30-day trends, revenue map")
                        featureRow(icon: "cylinder.split.1x2", color: .purple,
                                   title: "Firestore", desc: "Browse collection sizes and document counts")
                        featureRow(icon: "app.badge.fill", color: .orange,
                                   title: "App Versions", desc: "See which versions your users are running")
                    }
                    .padding(.horizontal)

                    // CTAs
                    VStack(spacing: 12) {
                        Button {
                            showAddProject = true
                        } label: {
                            Label("Add Firebase App", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(14)
                                .font(.headline)
                        }

                        Button {
                            showSettings = true
                        } label: {
                            Label("Open Settings", systemImage: "gearshape.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .foregroundColor(.primary)
                                .cornerRadius(14)
                                .font(.headline)
                        }
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 40)
                }
            }
            .sheet(isPresented: $showAddProject) {
                AddProjectView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    private func featureRow(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.15))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}
