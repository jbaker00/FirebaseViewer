import Foundation

// MARK: - Summary

struct AppStoreDownloadSummary {
    var totalDownloads: Int = 0
    var totalProceeds: Double = 0
    var appBreakdowns: [AppDownloadBreakdown] = []
    var dailyDownloads: [DailyDownload] = []
}

// MARK: - Per-app breakdown

struct AppDownloadBreakdown: Identifiable {
    let id = UUID()
    let appTitle: String
    let downloads: Int
    let proceeds: Double
}

// MARK: - Daily totals

struct DailyDownload: Identifiable {
    let id = UUID()
    let date: Date
    let downloads: Int
    let proceeds: Double
}

// MARK: - Raw row parsed from TSV

struct SalesReportRow {
    let title: String
    let units: Int
    let proceeds: Double
    let countryCode: String
    let productType: String
    let date: Date
}
