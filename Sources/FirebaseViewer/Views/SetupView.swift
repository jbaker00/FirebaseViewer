import SwiftUI
import UniformTypeIdentifiers

struct SetupView: View {
    @ObservedObject var config: ConfigurationService
    var onComplete: () -> Void

    @State private var showFileImporter = false
    @State private var importedJSON: String?
    @State private var importError: String?
    @State private var showProjectForm = false

    // Project form fields
    @State private var projectName = ""
    @State private var ga4PropertyID = ""
    @State private var gcpProjectID = ""
    @State private var firestoreProjectID = ""
    @State private var selectedColor: FirebaseProject.ProjectColor = .blue

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    serviceAccountSection
                    if config.hasServiceAccount {
                        projectsSection
                    }
                    if config.isConfigured {
                        continueButton
                    }
                }
                .padding()
            }
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.large)
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [UTType.json],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .sheet(isPresented: $showProjectForm) {
                addProjectSheet
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Welcome to Firebase Viewer")
                .font(.title.bold())

            Text("Connect your own Firebase & GCP account to get started. You'll need a service account JSON key from the Google Cloud Console.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var serviceAccountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Service Account", systemImage: "key.fill")
                .font(.headline)

            if config.hasServiceAccount {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Service account configured")
                        .font(.subheadline)
                    Spacer()
                    Button("Replace") {
                        showFileImporter = true
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Import your service account JSON key to enable Firebase Analytics, Cloud Logging, and Firestore access.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Import Service Account JSON", systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            if let error = importError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Firebase Projects", systemImage: "folder.fill")
                    .font(.headline)
                Spacer()
                Button {
                    showProjectForm = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
            }

            if config.projects.isEmpty {
                VStack(spacing: 8) {
                    Text("No projects configured yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Add a Firebase project to start viewing analytics.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(config.projects) { project in
                    ProjectRow(project: project) {
                        config.removeProject(id: project.id)
                    }
                }
            }
        }
    }

    private var continueButton: some View {
        Button {
            onComplete()
        } label: {
            Text("Continue")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .padding(.top, 8)
    }

    // MARK: - Add Project Sheet

    private var addProjectSheet: some View {
        NavigationStack {
            Form {
                Section("Project Details") {
                    TextField("Project Name", text: $projectName)
                    TextField("GCP Project ID (e.g. my-project-123)", text: $gcpProjectID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Analytics (Optional)") {
                    TextField("GA4 Property ID", text: $ga4PropertyID)
                        .keyboardType(.numberPad)
                }

                Section("Firestore (Optional)") {
                    TextField("Firestore Project ID", text: $firestoreProjectID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Appearance") {
                    Picker("Color", selection: $selectedColor) {
                        ForEach([FirebaseProject.ProjectColor.blue, .orange, .purple, .green, .red], id: \.self) { color in
                            HStack {
                                Circle().fill(color.color).frame(width: 12, height: 12)
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
                    Button("Cancel") { showProjectForm = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addProject()
                    }
                    .disabled(projectName.isEmpty || gcpProjectID.isEmpty)
                }
            }
        }
    }

    // MARK: - Actions

    private func handleFileImport(_ result: Result<[URL], Error>) {
        importError = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                importError = "Could not access the selected file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let data = try Data(contentsOf: url)
                // Validate it's a valid service account JSON
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let type = json?["type"] as? String, type == "service_account" else {
                    importError = "This doesn't look like a service account JSON. Expected \"type\": \"service_account\"."
                    return
                }
                guard let jsonString = String(data: data, encoding: .utf8) else {
                    importError = "Could not read file as UTF-8."
                    return
                }
                config.saveServiceAccount(json: jsonString)
                importedJSON = jsonString

                // Auto-detect GCP project ID
                if let projectID = json?["project_id"] as? String, gcpProjectID.isEmpty {
                    gcpProjectID = projectID
                }
            } catch {
                importError = "Could not read file: \(error.localizedDescription)"
            }

        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func addProject() {
        let project = FirebaseProject(
            id: UUID().uuidString,
            name: projectName,
            ga4PropertyID: ga4PropertyID.isEmpty ? nil : ga4PropertyID,
            streamIDs: nil,
            firestoreProjectID: firestoreProjectID.isEmpty ? nil : firestoreProjectID,
            gcpProjectID: gcpProjectID.isEmpty ? nil : gcpProjectID,
            admobAppName: nil,
            icon: "flame.fill",
            tintColor: selectedColor
        )
        config.addProject(project)

        // Reset form
        projectName = ""
        ga4PropertyID = ""
        gcpProjectID = ""
        firestoreProjectID = ""
        selectedColor = .blue
        showProjectForm = false
    }
}

// MARK: - Project Row

private struct ProjectRow: View {
    let project: FirebaseProject
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: project.icon)
                .font(.title3)
                .foregroundStyle(project.tintColor.color)
                .frame(width: 36, height: 36)
                .background(project.tintColor.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.subheadline.bold())
                if let gcp = project.gcpProjectID {
                    Text(gcp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                if project.hasAnalytics {
                    Image(systemName: "chart.bar.fill").font(.caption2).foregroundStyle(.blue)
                }
                if project.hasFirestore {
                    Image(systemName: "cylinder.split.1x2").font(.caption2).foregroundStyle(.green)
                }
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
