import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var analytics: AnalyticsService
    @EnvironmentObject private var projectStore: UserProjectStore

    @State private var showSAInput = false
    @State private var showAddProject = false

    var body: some View {
        NavigationStack {
            List {
                authSection
                customProjectsSection
                builtInProjectsSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showSAInput) {
                ServiceAccountInputView(isPresented: $showSAInput)
                    .environmentObject(projectStore)
            }
            .sheet(isPresented: $showAddProject) {
                AddProjectView()
                    .environmentObject(projectStore)
                    .environmentObject(analytics)
            }
        }
    }

    // MARK: - Authentication section

    private var authSection: some View {
        Section {
            if projectStore.hasCustomServiceAccount {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Custom Service Account")
                            .font(.subheadline.bold())
                        Text("Your credentials are saved securely")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Change") { showSAInput = true }
                        .font(.caption)
                        .buttonStyle(.bordered)
                }
                Button("Remove Credentials", role: .destructive) {
                    projectStore.saveServiceAccount("")
                    analytics.clearTokenCache()
                }
            } else if projectStore.hasBundledServiceAccount {
                HStack(spacing: 12) {
                    Image(systemName: "doc.badge.checkmark")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Built-in Service Account")
                            .font(.subheadline.bold())
                        Text("Using bundled credentials")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Add Custom Credentials") { showSAInput = true }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No Service Account")
                            .font(.subheadline.bold())
                        Text("Paste your Google service account JSON to load analytics")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Add Service Account JSON") { showSAInput = true }
                    .buttonStyle(.borderedProminent)
            }
        } header: {
            Text("Authentication")
        } footer: {
            Text("A Google Cloud service account JSON with the Analytics Data API (analytics.readonly) scope is required.")
        }
    }

    // MARK: - Custom projects section

    private var customProjectsSection: some View {
        Section {
            if projectStore.customProjects.isEmpty {
                Text("No custom projects yet")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(projectStore.customProjects) { project in
                    projectRow(project)
                }
                .onDelete { offsets in
                    let removedIDs = offsets.map { projectStore.customProjects[$0].id }
                    projectStore.removeProject(at: offsets)
                    if removedIDs.contains(analytics.selectedProject.id),
                       let first = projectStore.allProjects.first {
                        Task { await analytics.select(project: first) }
                    }
                }
            }
            Button {
                showAddProject = true
            } label: {
                Label("Add Firebase Project", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Custom Projects")
        } footer: {
            Text("Add your own Firebase projects by entering their GA4 property IDs.")
        }
    }

    // MARK: - Built-in projects section

    private var builtInProjectsSection: some View {
        Section("Built-in Projects") {
            ForEach(FirebaseProject.all) { project in
                projectRow(project)
            }
        }
    }

    private func projectRow(_ project: FirebaseProject) -> some View {
        HStack(spacing: 12) {
            Image(systemName: project.icon)
                .foregroundStyle(project.tintColor.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.subheadline.bold())
                if let id = project.ga4PropertyID {
                    Text("GA4: \(id)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                if let fid = project.firestoreProjectID {
                    Text("Firestore: \(fid)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Service Account Input Sheet

struct ServiceAccountInputView: View {
    @EnvironmentObject private var projectStore: UserProjectStore
    @Binding var isPresented: Bool

    @State private var jsonText = ""
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Paste the contents of your Google Cloud service account JSON key file. The account needs the **Analytics Data API** (`analytics.readonly`) scope enabled.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                TextEditor(text: $jsonText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
            .navigationTitle("Service Account JSON")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                jsonText = projectStore.serviceAccountJSON
            }
        }
    }

    private func save() {
        let trimmed = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["client_email"] != nil,
              obj["private_key"] != nil else {
            errorMessage = "Invalid JSON. Make sure it includes 'client_email' and 'private_key' fields."
            return
        }
        projectStore.saveServiceAccount(trimmed)
        isPresented = false
    }
}

// MARK: - Add Project Sheet

struct AddProjectView: View {
    @EnvironmentObject private var projectStore: UserProjectStore
    @EnvironmentObject private var analytics: AnalyticsService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var ga4PropertyID = ""
    @State private var firestoreProjectID = ""
    @State private var streamIDsText = ""
    @State private var selectedIcon = "flame.fill"
    @State private var selectedColor = FirebaseProject.ProjectColor.blue

    private let icons = [
        "flame.fill", "iphone", "laptopcomputer", "app.fill",
        "gamecontroller.fill", "cart.fill", "heart.fill",
        "star.fill", "bolt.fill", "globe"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Project Details") {
                    TextField("App / Project Name", text: $name)
                    TextField("GA4 Property ID (e.g. 123456789)", text: $ga4PropertyID)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Firestore Project ID (optional)", text: $firestoreProjectID)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Stream IDs, comma-separated (optional)", text: $streamIDsText)
                        .keyboardType(.numbersAndPunctuation)
                }

                Section("Appearance") {
                    Picker("Icon", selection: $selectedIcon) {
                        ForEach(icons, id: \.self) { icon in
                            Label(icon, systemImage: icon).tag(icon)
                        }
                    }
                    Picker("Color", selection: $selectedColor) {
                        ForEach(FirebaseProject.ProjectColor.allCases, id: \.self) { color in
                            HStack {
                                Circle()
                                    .fill(color.color)
                                    .frame(width: 12, height: 12)
                                Text(color.rawValue.capitalized)
                            }
                            .tag(color)
                        }
                    }
                }
            }
            .navigationTitle("Add Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addProject() }
                        .disabled(name.isEmpty || ga4PropertyID.isEmpty)
                }
            }
        }
    }

    private func addProject() {
        let streamIDs: [String]? = streamIDsText.isEmpty ? nil :
            streamIDsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        let project = FirebaseProject(
            id: UUID().uuidString,
            name: name,
            ga4PropertyID: ga4PropertyID,
            streamIDs: streamIDs,
            firestoreProjectID: firestoreProjectID.isEmpty ? nil : firestoreProjectID,
            admobAppName: nil,
            icon: selectedIcon,
            tintColor: selectedColor
        )
        projectStore.addProject(project)
        dismiss()
    }
}
