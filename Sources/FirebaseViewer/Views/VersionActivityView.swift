import SwiftUI
import Charts

// MARK: - Sessions & Events per Version (Today / Yesterday / 30 Days) + 7-Day Chart

private let activityDayFormatter: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "EEE\nd"; return f
}()

private struct ActivityBar: Identifiable {
    let id = UUID()
    let label: String
    let value: Int
    let metric: String
}

struct VersionActivityView: View {
    @EnvironmentObject private var analytics: AnalyticsService

    private var chartBars: [ActivityBar] {
        let days = analytics.dailyActivityStats
        let labels = days.map { activityDayFormatter.string(from: $0.date) }
        return days.enumerated().flatMap { i, day -> [ActivityBar] in [
            ActivityBar(label: labels[i], value: day.sessions,   metric: "Sessions"),
            ActivityBar(label: labels[i], value: day.eventCount, metric: "Events")
        ]}
    }

    private var chartDayLabels: [String] {
        analytics.dailyActivityStats.map { activityDayFormatter.string(from: $0.date) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                periodTable
                activityChart
            }
            .padding(.vertical)
        }
    }

    // MARK: - Period Table

    private var periodTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sessions & Events by Version")
                .font(.headline)
                .padding(.horizontal)

            if analytics.versionPeriodStats.isEmpty {
                Text("No data")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                // Header row
                periodHeaderRow
                    .padding(.horizontal)

                Divider().padding(.horizontal)

                ForEach(analytics.versionPeriodStats) { stat in
                    PeriodStatRow(stat: stat)
                        .padding(.horizontal)
                    Divider().padding(.horizontal)
                }
            }
        }
    }

    private var periodHeaderRow: some View {
        HStack(spacing: 0) {
            Text("Version")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(["Today", "Yesterday", "30 Days"], id: \.self) { label in
                VStack(spacing: 1) {
                    Text(label)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text("Sess")
                            .font(.caption2)
                            .foregroundStyle(.blue.opacity(0.8))
                        Text("Ev")
                            .font(.caption2)
                            .foregroundStyle(.green.opacity(0.8))
                    }
                }
                .frame(width: 90)
            }
        }
    }

    // MARK: - 7-Day Chart

    private var activityChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last 7 Days")
                .font(.headline)
                .padding(.horizontal)

            if analytics.dailyActivityStats.isEmpty {
                Text("No data")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                Chart(chartBars) { bar in
                    BarMark(
                        x: .value("Day", bar.label),
                        y: .value("Count", bar.value)
                    )
                    .foregroundStyle(by: .value("Metric", bar.metric))
                    .position(by: .value("Metric", bar.metric), axis: .horizontal)
                    .cornerRadius(3)
                }
                .chartXScale(domain: chartDayLabels)
                .chartForegroundStyleScale(["Sessions": Color.blue, "Events": Color.green])
                .chartLegend(position: .bottom, alignment: .center, spacing: 12)
                .frame(height: 240)
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Row

private struct PeriodStatRow: View {
    let stat: VersionPeriodStats

    var body: some View {
        HStack(spacing: 0) {
            VersionBadge(version: stat.version)
                .frame(maxWidth: .infinity, alignment: .leading)

            periodCell(sessions: stat.todaySessions, events: stat.todayEvents)
            periodCell(sessions: stat.yesterdaySessions, events: stat.yesterdayEvents)
            periodCell(sessions: stat.thirtyDaySessions, events: stat.thirtyDayEvents)
        }
        .padding(.vertical, 4)
    }

    private func periodCell(sessions: Int, events: Int) -> some View {
        HStack(spacing: 4) {
            Text(sessions.abbreviated)
                .font(.caption.bold())
                .foregroundStyle(.blue)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
            Text(events.abbreviated)
                .font(.caption)
                .foregroundStyle(.green)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
        .frame(width: 90)
    }
}
