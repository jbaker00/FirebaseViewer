import SwiftUI
import Charts

// MARK: - Sessions & Events per Version (Today / Yesterday / 30 Days) + 7-Day Chart

struct VersionActivityView: View {
    @EnvironmentObject private var analytics: AnalyticsService

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
                // Flatten daily stats into two series for grouped bars
                let chartData: [(date: Date, value: Int, metric: String)] =
                    analytics.dailyActivityStats.flatMap { day in
                        [(day.date, day.sessions, "Sessions"),
                         (day.date, day.eventCount, "Events")]
                    }

                Chart(chartData, id: \.metric) { item in
                    BarMark(
                        x: .value("Date", item.date, unit: .day),
                        y: .value("Count", item.value)
                    )
                    .foregroundStyle(by: .value("Metric", item.metric))
                    .position(by: .value("Metric", item.metric))
                    .cornerRadius(3)
                }
                .chartForegroundStyleScale([
                    "Sessions": Color.blue,
                    "Events":   Color.green
                ])
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                    }
                }
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
