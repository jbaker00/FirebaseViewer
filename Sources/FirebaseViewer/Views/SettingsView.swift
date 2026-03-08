import SwiftUI

struct SettingsView: View {
    @ObservedObject var config: ConfigurationService
    var onShowSetup: () -> Void

    @State private var showResetAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section("Service Account") {
                    if config.hasServiceAccount {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("User-provided service account")
                            Spacer()
                        }
                    } else if hasBundledServiceAccount() {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                            Text("Using bundled service account")
                            Spacer()
                        }
                    } else {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Text("No service account configured")
                            Spacer()
                        }
                    }
                }

                Section("Firebase Projects") {
                    if config.projects.isEmpty {
                        Text("Using default project configuration")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(config.projects) { project in
                            HStack {
                                Image(systemName: project.icon)
                                    .foregroundStyle(project.tintColor.color)
                                VStack(alignment: .leading) {
                                    Text(project.name)
                                        .font(.subheadline.bold())
                                    if let gcp = project.gcpProjectID {
                                        Text(gcp)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    Text("\(FirebaseProject.all.count) project(s) active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        onShowSetup()
                    } label: {
                        Label("Run Setup Again", systemImage: "wrench.and.screwdriver")
                    }

                    Button(role: .destructive) {
                        showResetAlert = true
                    } label: {
                        Label("Reset All Configuration", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Reset Configuration?", isPresented: $showResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    config.resetAll()
                }
            } message: {
                Text("This will remove your service account, project configurations, and AdMob credentials. You'll need to set up again.")
            }
        }
    }

    private func hasBundledServiceAccount() -> Bool {
        Bundle.main.url(forResource: "ServiceAccount", withExtension: "json") != nil
    }
}
