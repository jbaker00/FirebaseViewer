import Foundation

// MARK: - Analytics Data API models

struct RunReportRequest: Encodable {
    let dateRanges: [DateRange]
    let dimensions: [Dimension]
    let metrics: [Metric]
    let limit: Int?
    let dimensionFilter: DimensionFilter?

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

    // Filters to one or more streamId values
    struct DimensionFilter: Encodable {
        let orGroup: OrGroup?
        let filter: SingleFilter?

        struct OrGroup: Encodable {
            let expressions: [Expression]
            struct Expression: Encodable {
                let filter: SingleFilter
            }
        }
        struct SingleFilter: Encodable {
            let fieldName: String
            let stringFilter: StringFilter
            struct StringFilter: Encodable {
                let value: String
            }
        }
    }

    static func streamFilter(ids: [String]) -> DimensionFilter {
        if ids.count == 1 {
            return DimensionFilter(
                orGroup: nil,
                filter: .init(fieldName: "streamId", stringFilter: .init(value: ids[0]))
            )
        }
        let expressions = ids.map {
            DimensionFilter.OrGroup.Expression(
                filter: .init(fieldName: "streamId", stringFilter: .init(value: $0))
            )
        }
        return DimensionFilter(orGroup: .init(expressions: expressions), filter: nil)
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
