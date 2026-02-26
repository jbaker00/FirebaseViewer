import SwiftUI

/// Settings tab: manage Firebase projects, AdMob credentials, and sign-out.
struct SettingsView: View {
    @EnvironmentObject private var credentialStore: CredentialStore
    @EnvironmentObject private var admob: AdMobService
    @Environment(\.dismiss) private var dismiss

    @State private var showAddProject = false
    @State private var editingProject: FirebaseProject?
    @State private var showAdMobCredentials = false
    @State private var deleteConfirmProject: FirebaseProject?

    // AdMob credential fields
    @State private var admobClientID = ""
    @State private var admobClientSecret = ""
    @State private var admobGCPProject = ""

    var body: some View {
        NavigationStack {
            List {
                projectsSection
                admobSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if dismiss != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showAddProject) {
                AddProjectView()
            }
            .sheet(item: $editingProject) { project in
                EditProjectView(project: project)
            }
            .alert("Delete \(deleteConfirmProject?.name ?? "")?",
                   isPresented: Binding(
                       get: { deleteConfirmProject != nil },
                       set: { if !$0 { deleteConfirmProject = nil } }
                   )) {
                Button("Delete", role: .destructive) {
                    if let p = deleteConfirmProject {
                        credentialStore.deleteProject(id: p.id)
                    }
                    deleteConfirmProject = nil
                }
                Button("Cancel", role: .cancel) { deleteConfirmProject = nil }
            } message: {
                Text("This will remove the project and its saved credentials.")
            }
        }
        .onAppear {
            admobClientID     = credentialStore.admobClientID     == CredentialStore.defaultClientID     ? "" : credentialStore.admobClientID
            admobClientSecret = credentialStore.admobClientSecret == CredentialStore.defaultClientSecret ? "" : credentialStore.admobClientSecret
            admobGCPProject   = credentialStore.admobGCPProjectID
        }
    }

    // MARK: - Sections

    private var projectsSection: some View {
        Section {
            ForEach(credentialStore.projects) { project in
                projectRow(project)
            }
            Button {
                showAddProject = true
            } label: {
                Label("Add Firebase App", systemImage: "plus.circle.fill")
                    .foregroundColor(.accentColor)
            }
        } header: {
            Text("Firebase Apps")
        } footer: {
            if credentialStore.projects.isEmpty {
                Text("No apps configured. Tap Add Firebase App to get started.")
            }
        }
    }

    private func projectRow(_ project: FirebaseProject) -> some View {
        HStack {
            Image(systemName: project.icon)
                .foregroundColor(project.tintColor.color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name).font(.headline)
                Group {
                    if let pid = project.ga4PropertyID {
                        Text("GA4: \(pid)")
                    }
                    if let fid = project.firestoreProjectID {
                        Text("Firestore: \(fid)")
                    }
                    if let admob = project.admobAppName {
                        Text("AdMob: \(admob)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // SA status badge
            let hasSA = credentialStore.serviceAccountJSON(for: project.id) != nil
            Image(systemName: hasSA ? "key.fill" : "key.slash.fill")
                .foregroundColor(hasSA ? .green : .orange)
                .font(.caption)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteConfirmProject = project
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                editingProject = project
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    private var admobSection: some View {
        Section("AdMob") {
            if admob.isAuthorized {
                HStack {
                    Label("Connected to AdMob", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Spacer()
                    Button("Sign Out") {
                        admob.signOut()
                    }
                    .foregroundColor(.red)
                    .font(.caption)
                }
            } else {
                Button {
                    Task { await admob.signIn() }
                } label: {
                    Label("Connect AdMob Account", systemImage: "dollarsign.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }

            DisclosureGroup("OAuth Client (Advanced)", isExpanded: $showAdMobCredentials) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Leave blank to use the default client. Only change if you have your own Google Cloud OAuth client.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Client ID (optional)", text: $admobClientID)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.caption)

                    SecureField("Client Secret (optional)", text: $admobClientSecret)
                        .autocorrectionDisabled()
                        .font(.caption)

                    TextField("GCP Project ID for quota", text: $admobGCPProject)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.caption)

                    Button("Save AdMob Credentials") {
                        credentialStore.saveAdMobCredentials(
                            clientID: admobClientID,
                            clientSecret: admobClientSecret,
                            gcpProjectID: admobGCPProject
                        )
                        showAdMobCredentials = false
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)

                    if admobClientID.isEmpty {
                        Button("Reset to Default") {
                            credentialStore.resetAdMobCredentials()
                            admobClientID = ""
                            admobClientSecret = ""
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    .foregroundStyle(.secondary)
            }
            Link("Firebase Analytics Docs",
                 destination: URL(string: "https://developers.google.com/analytics/devguides/reporting/data/v1")!)
            Link("AdMob API Docs",
                 destination: URL(string: "https://developers.google.com/admob/api/v1/reference/rest")!)
        }
    }
}

// MARK: - Edit Project Sheet

struct EditProjectView: View {
    @EnvironmentObject private var credentialStore: CredentialStore
    @Environment(\.dismiss) private var dismiss

    let project: FirebaseProject

    @State private var name: String
    @State private var selectedIcon: String
    @State private var selectedColor: FirebaseProject.ProjectColor
    @State private var ga4PropertyID: String
    @State private var streamIDsText: String
    @State private var firestoreProjectID: String
    @State private var admobAppName: String
    @State private var newSAJSON = ""
    @State private var newFirestoreSAJSON = ""
    @State private var saValidated = false
    @State private var saValidationError = ""

    init(project: FirebaseProject) {
        self.project = project
        _name               = State(initialValue: project.name)
        _selectedIcon       = State(initialValue: project.icon)
        _selectedColor      = State(initialValue: project.tintColor)
        _ga4PropertyID      = State(initialValue: project.ga4PropertyID ?? "")
        _streamIDsText      = State(initialValue: project.streamIDs?.joined(separator: ", ") ?? "")
        _firestoreProjectID = State(initialValue: project.firestoreProjectID ?? "")
        _admobAppName       = State(initialValue: project.admobAppName ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("App Info") {
                    TextField("App Name", text: $name)
                }
                Section("GA4 Property ID") {
                    TextField("e.g. 123456789", text: $ga4PropertyID)
                        .keyboardType(.numberPad)
                }
                Section("Stream IDs (comma-separated, optional)") {
                    TextField("e.g. 123456, 789012", text: $streamIDsText)
                }
                Section("Firestore Project ID (optional)") {
                    TextField("e.g. my-project", text: $firestoreProjectID)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section("AdMob App Name (optional)") {
                    TextField("Exact display name in AdMob", text: $admobAppName)
                }
                Section("Replace Service Account JSON") {
                    if saValidated {
                        Label("New service account validated ✓", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Clear") { newSAJSON = ""; saValidated = false }.font(.caption)
                    } else {
                        let hasCurrent = credentialStore.serviceAccountJSON(for: project.id) != nil
                        if hasCurrent {
                            Text("A service account is already saved. Paste below to replace it.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        TextEditor(text: $newSAJSON)
                            .frame(minHeight: 80)
                            .font(.system(.caption, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if !saValidationError.isEmpty {
                            Text(saValidationError).foregroundStyle(.red).font(.caption)
                        }
                        if !newSAJSON.isEmpty {
                            Button("Validate") { validateSA() }.font(.caption)
                        }
                    }
                }
                Section("Replace Firestore Service Account (optional)") {
                    TextEditor(text: $newFirestoreSAJSON)
                        .frame(minHeight: 60)
                        .font(.system(.caption, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Edit \(project.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.isEmpty)
                }
            }
        }
    }

    private func validateSA() {
        struct MinimalSA: Decodable { let type: String; let project_id: String; let client_email: String; let private_key: String }
        guard let data = newSAJSON.data(using: .utf8),
              let _ = try? JSONDecoder().decode(MinimalSA.self, from: data) else {
            saValidationError = "Invalid service account JSON"
            return
        }
        saValidationError = ""
        saValidated = true
    }

    private func save() {
        let streamIDs: [String]? = streamIDsText.isEmpty ? nil :
            streamIDsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        let updated = FirebaseProject(
            id: project.id,
            name: name,
            ga4PropertyID: ga4PropertyID.isEmpty ? nil : ga4PropertyID,
            streamIDs: streamIDs,
            firestoreProjectID: firestoreProjectID.isEmpty ? nil : firestoreProjectID,
            admobAppName: admobAppName.isEmpty ? nil : admobAppName,
            icon: selectedIcon,
            tintColor: selectedColor
        )
        credentialStore.updateProject(updated)
        if saValidated && !newSAJSON.isEmpty {
            credentialStore.setServiceAccount(json: newSAJSON, for: project.id)
        }
        if !newFirestoreSAJSON.isEmpty {
            credentialStore.setFirestoreServiceAccount(json: newFirestoreSAJSON, for: project.id)
        }
        dismiss()
    }
}
