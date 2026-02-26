import SwiftUI

/// Multi-step sheet for adding a new Firebase project.
struct AddProjectView: View {
    @EnvironmentObject private var credentialStore: CredentialStore
    @Environment(\.dismiss) private var dismiss

    // Step management
    @State private var step = 1

    // Step 1: Basic info
    @State private var name = ""
    @State private var selectedIcon = "star.fill"
    @State private var selectedColor: FirebaseProject.ProjectColor = .blue

    // Step 2: GA4 Analytics
    @State private var ga4PropertyID = ""
    @State private var streamIDsText = ""   // comma-separated
    @State private var serviceAccountJSON = ""
    @State private var saValidationError = ""
    @State private var saValidated = false

    // Step 3: Firestore (optional)
    @State private var firestoreProjectID = ""
    @State private var useSeperateFirestoreSA = false
    @State private var firestoreSAJSON = ""

    // Step 4: AdMob (optional)
    @State private var admobAppName = ""

    private let colors: [FirebaseProject.ProjectColor] = [.orange, .blue, .purple, .green, .red]

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case 1: step1View
                case 2: step2View
                case 3: step3View
                case 4: step4View
                default: step1View
                }
            }
            .navigationTitle("Add Firebase App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if step < 4 {
                        Button("Next") { step += 1 }
                            .disabled(!canAdvance)
                    } else {
                        Button("Save") { saveProject() }
                            .disabled(name.isEmpty)
                    }
                }
            }
        }
    }

    // MARK: - Step 1: Name & Appearance

    private var step1View: some View {
        Form {
            Section("App Name") {
                TextField("e.g. My Awesome App", text: $name)
            }

            Section("Icon") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(FirebaseProject.availableIcons, id: \.self) { icon in
                        Button {
                            selectedIcon = icon
                        } label: {
                            Image(systemName: icon)
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(selectedIcon == icon ? selectedColor.color.opacity(0.2) : Color.clear)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedIcon == icon ? selectedColor.color : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(selectedIcon == icon ? selectedColor.color : .primary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Color") {
                HStack(spacing: 16) {
                    ForEach(colors, id: \.rawValue) { c in
                        Button {
                            selectedColor = c
                        } label: {
                            Circle()
                                .fill(c.color)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle().stroke(Color.white, lineWidth: selectedColor == c ? 3 : 0)
                                )
                                .shadow(color: c.color.opacity(0.4), radius: selectedColor == c ? 4 : 0)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Step 2: GA4 Analytics

    private var step2View: some View {
        Form {
            Section {
                Text("Connect this app to Google Analytics (GA4). You'll need a GA4 Property ID and a service account JSON file with Viewer access.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("GA4 Property ID") {
                TextField("e.g. 123456789", text: $ga4PropertyID)
                    .keyboardType(.numberPad)
                Text("Find this in GA4 → Admin → Property Settings → Property ID")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Stream IDs (Optional)") {
                TextField("e.g. 123456, 789012", text: $streamIDsText)
                    .keyboardType(.numbersAndPunctuation)
                Text("Comma-separated. Leave blank to include all streams.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Service Account JSON") {
                if saValidated {
                    Label("Service account validated ✓", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("Replace") { serviceAccountJSON = ""; saValidated = false }
                        .font(.caption)
                } else {
                    TextEditor(text: $serviceAccountJSON)
                        .frame(minHeight: 120)
                        .font(.system(.caption, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !saValidationError.isEmpty {
                        Text(saValidationError).foregroundStyle(.red).font(.caption)
                    }
                    Button("Validate JSON") { validateSA() }
                        .disabled(serviceAccountJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section {
                Text("Download the JSON from Google Cloud Console → IAM & Admin → Service Accounts → Keys → Add Key → JSON.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Step 3: Firestore (optional)

    private var step3View: some View {
        Form {
            Section {
                Text("Optional: Connect to Cloud Firestore to view document counts.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Firestore Project ID") {
                TextField("e.g. my-project-id", text: $firestoreProjectID)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Text("The GCP project ID where Firestore lives (often same as Firebase project ID).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !firestoreProjectID.isEmpty {
                Section {
                    Toggle("Use a separate service account for Firestore", isOn: $useSeperateFirestoreSA)
                    Text("Leave off to reuse the GA4 service account. Enable if Firestore lives in a different GCP project.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if useSeperateFirestoreSA {
                    Section("Firestore Service Account JSON") {
                        TextEditor(text: $firestoreSAJSON)
                            .frame(minHeight: 100)
                            .font(.system(.caption, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }
            }
        }
    }

    // MARK: - Step 4: AdMob (optional)

    private var step4View: some View {
        Form {
            Section {
                Text("Optional: Link this app to AdMob to see per-app revenue.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("AdMob App Name") {
                TextField("e.g. My Awesome App", text: $admobAppName)
                Text("Must match the display label exactly as it appears in your AdMob account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("You can find app display labels in AdMob → Apps → the name shown in the app list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Logic

    private var canAdvance: Bool {
        switch step {
        case 1: return !name.isEmpty
        case 2: return true // GA4 is optional — user can skip
        case 3: return true
        default: return true
        }
    }

    private func validateSA() {
        let trimmed = serviceAccountJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            saValidationError = "Invalid text encoding"
            return
        }
        struct MinimalSA: Decodable {
            let type: String
            let project_id: String
            let client_email: String
            let private_key: String
        }
        do {
            _ = try JSONDecoder().decode(MinimalSA.self, from: data)
            saValidationError = ""
            saValidated = true
        } catch {
            saValidationError = "Invalid service account JSON: \(error.localizedDescription)"
        }
    }

    private func saveProject() {
        let streamIDs: [String]? = streamIDsText.isEmpty ? nil :
            streamIDsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        let project = FirebaseProject(
            id: UUID().uuidString,
            name: name,
            ga4PropertyID: ga4PropertyID.isEmpty ? nil : ga4PropertyID,
            streamIDs: streamIDs,
            firestoreProjectID: firestoreProjectID.isEmpty ? nil : firestoreProjectID,
            admobAppName: admobAppName.isEmpty ? nil : admobAppName,
            icon: selectedIcon,
            tintColor: selectedColor
        )
        credentialStore.addProject(project)

        if !serviceAccountJSON.isEmpty {
            credentialStore.setServiceAccount(json: serviceAccountJSON, for: project.id)
        }
        if !firestoreSAJSON.isEmpty && useSeperateFirestoreSA {
            credentialStore.setFirestoreServiceAccount(json: firestoreSAJSON, for: project.id)
        }
        dismiss()
    }
}
