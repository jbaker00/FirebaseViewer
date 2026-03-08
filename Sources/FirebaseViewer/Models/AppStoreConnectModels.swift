import Foundation

// MARK: - App Store Connect API Response Types

struct AppStoreConnectSalesReport: Identifiable {
    let id = UUID()
    let appName: String
    let units: Int
    let date: Date
    let countryCode: String
    let deviceType: String
    let productType: ProductType

    enum ProductType: String {
        case freeOrPaid = "1"           // Free or paid app download
        case update = "7"               // Update
        case redownload = "3"           // Re-download
        case inAppPurchase = "IA1"      // In-app purchase
        case unknown

        var label: String {
            switch self {
            case .freeOrPaid:     return "Download"
            case .update:         return "Update"
            case .redownload:     return "Re-Download"
            case .inAppPurchase:  return "In-App Purchase"
            case .unknown:        return "Other"
            }
        }
    }
}

struct AppStoreConnectDailySummary: Identifiable {
    let id = UUID()
    let date: Date
    let totalUnits: Int
    let downloads: Int
    let updates: Int
    let redownloads: Int
}

struct AppStoreConnectCountryStats: Identifiable {
    let id: String // countryCode
    let countryCode: String
    let countryName: String
    let totalUnits: Int
    let downloads: Int

    var coordinate: (lat: Double, lng: Double)? {
        CountryCoordinates.coordinate(for: countryName)
            ?? CountryCoordinates.coordinateFromISO(countryCode)
    }
}

struct AppStoreConnectOverview {
    var totalDownloads: Int = 0
    var totalUpdates: Int = 0
    var totalRedownloads: Int = 0
    var uniqueCountries: Int = 0
    var dailySummaries: [AppStoreConnectDailySummary] = []
    var countryStats: [AppStoreConnectCountryStats] = []
    var deviceBreakdown: [String: Int] = [:]
}

// MARK: - App Store Connect API Types

struct AppStoreConnectApp: Identifiable, Decodable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let name: String
        let bundleId: String
    }
}

struct AppStoreConnectAppsResponse: Decodable {
    let data: [AppStoreConnectApp]
}
