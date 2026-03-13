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
        var name: String?
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

    static func eventFilter(names: [String]) -> DimensionFilter {
        if names.count == 1 {
            return DimensionFilter(
                orGroup: nil,
                filter: .init(fieldName: "eventName", stringFilter: .init(value: names[0]))
            )
        }
        let expressions = names.map {
            DimensionFilter.OrGroup.Expression(
                filter: .init(fieldName: "eventName", stringFilter: .init(value: $0))
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

// MARK: - TTS quota models

struct TTSQuotaStats {
    var openAIQuotaExceededCount: Int = 0
    var fallbackToComputerCount: Int = 0
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

struct VersionCountryStats: Identifiable {
    let id = UUID()
    let version: String
    let country: String
    let activeUsers: Int
}

struct VersionPeriodStats: Identifiable {
    let id = UUID()
    let version: String
    let todaySessions: Int
    let todayEvents: Int
    let yesterdaySessions: Int
    let yesterdayEvents: Int
    let thirtyDaySessions: Int
    let thirtyDayEvents: Int
}

struct DailyActivityStats: Identifiable {
    let id = UUID()
    let date: Date
    let sessions: Int
    let eventCount: Int
}

// MARK: - Firestore models

struct FirestoreCollectionStats: Identifiable {
    let id = UUID()
    let name: String
    let documentCount: Int
}

// MARK: - AdMob models

struct AdMobStats {
    var totalEarnings: Double = 0
    var impressions: Int = 0
    var clicks: Int = 0
    var ecpm: Double = 0
}

struct AdMobAppStats: Identifiable {
    let id = UUID()
    let appName: String
    let earnings: Double
    let impressions: Int
}

// MARK: - Multi-period AdMob report

struct AdMobPeriodReport {
    let label: String
    let earnings: Double
    let impressions: Int
    let clicks: Int
    let adRequests: Int
    let appBreakdown: [AppRow]
    let countryBreakdown: [CountryRow]

    struct AppRow: Identifiable {
        let id = UUID()
        let name: String
        let earnings: Double
        let impressions: Int
        let clicks: Int
    }

    struct CountryRow: Identifiable {
        let id = UUID()
        let code: String
        let name: String
        let earnings: Double
        let impressions: Int
        let clicks: Int
    }
}

struct AdMobCountryStats: Identifiable {
    let id = UUID()
    let countryCode: String   // ISO 3166-1 alpha-2 e.g. "US"
    let countryName: String   // display name for lookup in CountryCoordinates
    let earnings: Double
    let impressions: Int
    let appBreakdown: [AppEntry]  // per-app within this country

    struct AppEntry: Identifiable {
        let id = UUID()
        let appName: String
        let earnings: Double
        let impressions: Int
    }

    var coordinate: (lat: Double, lng: Double)? {
        CountryCoordinates.coordinate(for: countryName)
    }
}
