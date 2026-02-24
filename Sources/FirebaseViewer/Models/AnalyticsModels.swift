import Foundation

// MARK: - Analytics Data API models

struct RunReportRequest: Encodable {
    let dateRanges: [DateRange]
    let dimensions: [Dimension]
    let metrics: [Metric]
    let limit: Int?

    struct DateRange: Encodable {
        let startDate: String
        let endDate: String
    }
    struct Dimension: Encodable {
        let name: String
    }
    struct Metric: Encodable {
        let name: String
    }
}

struct RunReportResponse: Decodable {
    let rows: [Row]?
    let rowCount: Int?

    struct Row: Decodable {
        let dimensionValues: [DimensionValue]?
        let metricValues: [MetricValue]
    }
    struct DimensionValue: Decodable {
        let value: String
    }
    struct MetricValue: Decodable {
        let value: String
    }
}

// MARK: - Dashboard models

struct DashboardStats {
    var activeUsers: Int = 0
    var newUsers: Int = 0
    var sessions: Int = 0
    var eventCount: Int = 0
    var screenViews: Int = 0
}

struct AppVersionStats: Identifiable {
    let id = UUID()
    let version: String
    let osVersion: String
    let activeUsers: Int
    let sessions: Int
    let eventCount: Int
    let crashes: Int
}

struct CountryUserCount: Identifiable {
    let id = UUID()
    let country: String
    let userCount: Int
    let coordinate: (lat: Double, lng: Double)?
}
