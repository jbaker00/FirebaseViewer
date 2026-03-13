import Foundation
import Security
import CryptoKit
import zlib

// MARK: - App Store Connect API Service

@MainActor
final class AppStoreConnectService: ObservableObject {

    @Published var overview = AppStoreConnectOverview()
    @Published var apps: [AppStoreConnectApp] = []
    @Published var selectedAppID: String?
    @Published var isLoading = false
    @Published var error: String?
    @Published var isConfigured = false

    private var keyID: String = ""
    private var issuerID: String = ""
    private var privateKeyPEM: String = ""
    private var vendorNumber: String = ""
    private var tokenCache: (token: String, expiry: Date)?

    // Keychain keys
    private static let keychainKeyID       = "asc_key_id"
    private static let keychainIssuerID    = "asc_issuer_id"
    private static let keychainPrivateKey  = "asc_private_key_pem"
    private static let keychainVendorNumber = "asc_vendor_number_v2"

    // Default identifiers (not secret — the .p8 private key is the secret)
    private static let defaultKeyID       = "597FS4329D"
    private static let defaultIssuerID    = "69a6de71-bcfd-47e3-e053-5b8c7c11a4d1"
    private static let defaultVendorNumber = "83866591"

    // MARK: - Configuration

    func configure() {
        loadOrSeedCredentials()
        isConfigured = !keyID.isEmpty && !issuerID.isEmpty && !privateKeyPEM.isEmpty
        if !isConfigured {
            error = "App Store Connect credentials not found. Ensure AuthKey_\(Self.defaultKeyID).p8 is in the app Resources."
        }
    }

    private func loadOrSeedCredentials() {
        // Try Keychain first (fastest path after first launch)
        if let kid  = KeychainService.load(Self.keychainKeyID),
           let iid  = KeychainService.load(Self.keychainIssuerID),
           let pkey = KeychainService.load(Self.keychainPrivateKey),
           !kid.isEmpty, !pkey.isEmpty {
            keyID         = kid
            issuerID      = iid
            privateKeyPEM = pkey
            vendorNumber  = KeychainService.load(Self.keychainVendorNumber) ?? ""
            AppLogger.log("App Store Connect loaded from Keychain (Key: \(keyID), vendor: \(vendorNumber.isEmpty ? "unknown" : vendorNumber))", tag: "ASC")
            return
        }

        // First launch — read bundled .p8 resource and seed Keychain
        guard let keyURL = Bundle.main.url(forResource: "AuthKey_\(Self.defaultKeyID)", withExtension: "p8"),
              let pem = try? String(contentsOf: keyURL, encoding: .utf8) else {
            AppLogger.error("AuthKey_\(Self.defaultKeyID).p8 not found in bundle", tag: "ASC")
            return
        }

        keyID         = Self.defaultKeyID
        issuerID      = Self.defaultIssuerID
        privateKeyPEM = pem
        vendorNumber  = Self.defaultVendorNumber

        KeychainService.save(Self.keychainKeyID,       value: keyID)
        KeychainService.save(Self.keychainIssuerID,    value: issuerID)
        KeychainService.save(Self.keychainPrivateKey,  value: privateKeyPEM)
        KeychainService.save(Self.keychainVendorNumber, value: vendorNumber)
        AppLogger.log("App Store Connect seeded into Keychain from bundle (Key: \(keyID))", tag: "ASC")
    }

    // MARK: - Public

    func loadAll() async {
        guard isConfigured else { return }
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let token = try getToken()

            apps = try await fetchApps(token: token)
            AppLogger.log("Fetched \(apps.count) apps from App Store Connect", tag: "ASC")

            let reports = try await fetchSalesReports(token: token, days: 30)
            overview = buildOverview(from: reports)
        } catch {
            self.error = error.localizedDescription
            AppLogger.error("ASC load failed: \(error.localizedDescription)", tag: "ASC")
        }
    }

    // MARK: - JWT Authentication (ES256)

    private func getToken() throws -> String {
        if let cached = tokenCache, Date() < cached.expiry {
            return cached.token
        }

        let token = try buildJWT()
        tokenCache = (token, Date().addingTimeInterval(1100)) // ~18 minutes (max 20)
        return token
    }

    private func buildJWT() throws -> String {
        let now = Int(Date().timeIntervalSince1970)

        let header: [String: Any] = ["alg": "ES256", "kid": keyID, "typ": "JWT"]
        let payload: [String: Any] = [
            "iss": issuerID,
            "iat": now,
            "exp": now + 1200,
            "aud": "appstoreconnect-v1"
        ]

        let headerB64  = try base64URLEncode(JSONSerialization.data(withJSONObject: header))
        let payloadB64 = try base64URLEncode(JSONSerialization.data(withJSONObject: payload))
        let signingInput = "\(headerB64).\(payloadB64)"

        // CryptoKit handles Apple's PKCS#8 .p8 format natively
        let privateKey = try P256.Signing.PrivateKey(pemRepresentation: privateKeyPEM)
        let signature  = try privateKey.signature(for: Data(signingInput.utf8))
        // rawRepresentation is already the 64-byte r||s format JWT ES256 requires
        let sigB64 = base64URLEncode(signature.rawRepresentation)

        return "\(signingInput).\(sigB64)"
    }

    // MARK: - API calls

    private func fetchApps(token: String) async throws -> [AppStoreConnectApp] {
        let url = URL(string: "https://api.appstoreconnect.apple.com/v1/apps?fields[apps]=name,bundleId")!
        let data = try await apiRequest(url: url, token: token)
        let response = try JSONDecoder().decode(AppStoreConnectAppsResponse.self, from: data)
        return response.data
    }

    private func fetchSalesReports(token: String, days: Int) async throws -> [AppStoreConnectSalesReport] {
        var allReports: [AppStoreConnectSalesReport] = []
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for dayOffset in 1...days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let dateStr = dateFormatter.string(from: date)

            var components = URLComponents(string: "https://api.appstoreconnect.apple.com/v1/salesReports")!
            components.queryItems = [
                URLQueryItem(name: "filter[frequency]",      value: "DAILY"),
                URLQueryItem(name: "filter[reportDate]",     value: dateStr),
                URLQueryItem(name: "filter[reportSubType]",  value: "SUMMARY"),
                URLQueryItem(name: "filter[reportType]",     value: "SALES"),
                URLQueryItem(name: "filter[vendorNumber]",   value: vendorNumber)
            ]

            do {
                let data = try await apiRequest(url: components.url!, token: token)
                let reports = parseSalesReport(data: data, date: date)
                allReports.append(contentsOf: reports)
            } catch let err as NSError where err.code == 404 {
                continue  // report not yet available for this date
            } catch {
                AppLogger.error("Sales report \(dateStr): \(error.localizedDescription)", tag: "ASC")
                continue
            }
        }

        AppLogger.log("Fetched \(allReports.count) report rows over \(days) days", tag: "ASC")
        return allReports
    }

    private func apiRequest(url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Let URLSession handle Accept-Encoding/gzip automatically
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 404 {
                throw NSError(domain: "ASC", code: 404, userInfo: [NSLocalizedDescriptionKey: "Report not available"])
            }
            if httpResponse.statusCode != 200 {
                let body = String(data: data, encoding: .utf8) ?? "no body"
                AppLogger.error("ASC HTTP \(httpResponse.statusCode): \(body)", tag: "ASC")
                throw NSError(domain: "ASC", code: httpResponse.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(body)"])
            }
        }

        return data
    }

    // MARK: - Gzip decompression (Apple Sales Reports are always gzip-compressed)

    private func gunzip(_ data: Data) -> Data? {
        guard data.count > 2, data[0] == 0x1f, data[1] == 0x8b else { return nil }
        var stream = z_stream()
        // windowBits 47 = 16 + MAX_WBITS tells zlib to expect gzip wrapper
        guard inflateInit2_(&stream, 47, ZLIB_VERSION,
                            Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        var output = Data()
        let chunkSize = 65_536

        data.withUnsafeBytes { raw in
            stream.next_in  = UnsafeMutablePointer(mutating: raw.bindMemory(to: Bytef.self).baseAddress!)
            stream.avail_in = uInt(data.count)
            var buf = [Bytef](repeating: 0, count: chunkSize)
            repeat {
                buf.withUnsafeMutableBufferPointer { ptr in
                    stream.next_out  = ptr.baseAddress
                    stream.avail_out = uInt(chunkSize)
                    inflate(&stream, Z_NO_FLUSH)
                    let written = chunkSize - Int(stream.avail_out)
                    output.append(contentsOf: ptr[0..<written])
                }
            } while stream.avail_out == 0
        }
        return output.isEmpty ? nil : output
    }

    // MARK: - Parse TSV sales report

    private func parseSalesReport(data: Data, date: Date) -> [AppStoreConnectSalesReport] {
        let raw = gunzip(data) ?? data
        guard let text = String(data: raw, encoding: .utf8) else { return [] }
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 1 else { return [] }

        // TSV columns: Provider, Provider Country, SKU, Developer, Title, Version, Product Type Identifier,
        // Units, Developer Proceeds, Begin Date, End Date, Customer Currency, Country Code, ...
        // (Apple TSV format)
        var reports: [AppStoreConnectSalesReport] = []

        for line in lines.dropFirst() {
            let columns = line.components(separatedBy: "\t")
            guard columns.count >= 13 else { continue }

            let appName = columns[4].trimmingCharacters(in: .whitespaces)
            let productTypeRaw = columns[6].trimmingCharacters(in: .whitespaces)
            let units = Int(columns[7].trimmingCharacters(in: .whitespaces)) ?? 0
            let countryCode = columns[12].trimmingCharacters(in: .whitespaces)
            let device = columns.count > 17 ? columns[17].trimmingCharacters(in: .whitespaces) : "Unknown"

            let productType = AppStoreConnectSalesReport.ProductType(rawValue: productTypeRaw) ?? .unknown

            reports.append(AppStoreConnectSalesReport(
                appName: appName,
                units: units,
                date: date,
                countryCode: countryCode,
                deviceType: device,
                productType: productType
            ))
        }

        return reports
    }

    // MARK: - Build overview from reports

    private func buildOverview(from reports: [AppStoreConnectSalesReport]) -> AppStoreConnectOverview {
        var overview = AppStoreConnectOverview()

        // Filter by selected app if one is chosen
        let filtered: [AppStoreConnectSalesReport]
        if let appID = selectedAppID, let app = apps.first(where: { $0.id == appID }) {
            filtered = reports.filter { $0.appName == app.attributes.name }
        } else {
            filtered = reports
        }

        // Totals
        for report in filtered {
            switch report.productType {
            case .freeOrPaid:    overview.totalDownloads += report.units
            case .update:        overview.totalUpdates += report.units
            case .redownload:    overview.totalRedownloads += report.units
            default: break
            }
            overview.deviceBreakdown[report.deviceType, default: 0] += report.units
        }

        // Daily summaries
        let grouped = Dictionary(grouping: filtered, by: { Calendar.current.startOfDay(for: $0.date) })
        overview.dailySummaries = grouped.map { date, dayReports in
            var downloads = 0, updates = 0, redownloads = 0
            for r in dayReports {
                switch r.productType {
                case .freeOrPaid:   downloads += r.units
                case .update:       updates += r.units
                case .redownload:   redownloads += r.units
                default: break
                }
            }
            return AppStoreConnectDailySummary(
                date: date,
                totalUnits: downloads + updates + redownloads,
                downloads: downloads,
                updates: updates,
                redownloads: redownloads
            )
        }.sorted { $0.date < $1.date }

        // Country breakdown
        var countryTotals: [String: (downloads: Int, total: Int)] = [:]
        for report in filtered where report.productType == .freeOrPaid || report.productType == .redownload {
            countryTotals[report.countryCode, default: (0, 0)].total += report.units
            if report.productType == .freeOrPaid {
                countryTotals[report.countryCode, default: (0, 0)].downloads += report.units
            }
        }
        overview.countryStats = countryTotals.map { code, stats in
            let name = CountryCoordinates.isoCodeTable[code] ?? code
            return AppStoreConnectCountryStats(
                id: code,
                countryCode: code,
                countryName: name,
                totalUnits: stats.total,
                downloads: stats.downloads
            )
        }.sorted { $0.totalUnits > $1.totalUnits }

        overview.uniqueCountries = overview.countryStats.count

        return overview
    }

    // MARK: - Helpers

    private func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func base64URLEncode(_ string: String) throws -> String {
        guard let data = string.data(using: .utf8) else { throw ASCError.encodingFailed }
        return base64URLEncode(data)
    }
}

// MARK: - Errors

enum ASCError: LocalizedError {
    case signingFailed(String)
    case encodingFailed
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .signingFailed(let msg):  return "JWT signing failed: \(msg)"
        case .encodingFailed:          return "UTF-8 encoding failed."
        case .notConfigured:           return "App Store Connect is not configured."
        }
    }
}
