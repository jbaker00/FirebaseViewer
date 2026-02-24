import SwiftUI

struct ProjectPickerView: View {
    @EnvironmentObject private var analytics: AnalyticsService

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(FirebaseProject.all) { project in
                    ProjectChip(
                        project: project,
                        isSelected: analytics.selectedProject == project
                    )
                    .onTapGesture {
                        Task { await analytics.select(project: project) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }
}

private struct ProjectChip: View {
    let project: FirebaseProject
    let isSelected: Bool

    private var color: Color {
        switch project.tintColor {
        case .orange: return .orange
        case .blue:   return .blue
        case .purple: return .purple
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: project.icon)
                .font(.subheadline)
            Text(project.name)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
        }
        .foregroundStyle(isSelected ? .white : color)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            isSelected ? color : color.opacity(0.12),
            in: Capsule()
        )
        .overlay(
            Capsule().stroke(color.opacity(isSelected ? 0 : 0.4), lineWidth: 1)
        )
        .animation(.spring(response: 0.25), value: isSelected)
    }
}
