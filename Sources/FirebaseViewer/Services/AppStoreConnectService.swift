import Foundation
import CryptoKit
import Compression

// MARK: - App Store Connect API service

@MainActor
final class AppStoreConnectService: ObservableObject {

    @Published var isConfigured = false
    @Published var summary = AppStoreDownloadSummary()
    @Published var isLoading = false
    @Published var error: String?

    // Keychain keys
    private let keyIDKey        = "asc_key_id"
    private let issuerIDKey     = "asc_issuer_id"
    private let vendorNumberKey = "asc_vendor_number"
    private let privateKeyKey   = "asc_private_key"

    private static let reportDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    // MARK: - Init

    init() {
        isConfigured = KeychainService.load(keyIDKey) != nil &&
                       KeychainService.load(issuerIDKey) != nil &&
                       KeychainService.load(vendorNumberKey) != nil &&
                       KeychainService.load(privateKeyKey) != nil
    }

    // MARK: - Credentials

    func configure(keyID: String, issuerID: String, vendorNumber: String, privateKey: String) {
        KeychainService.save(keyIDKey,        value: keyID.trimmingCharacters(in: .whitespacesAndNewlines))
        KeychainService.save(issuerIDKey,     value: issuerID.trimmingCharacters(in: .whitespacesAndNewlines))
        KeychainService.save(vendorNumberKey, value: vendorNumber.trimmingCharacters(in: .whitespacesAndNewlines))
        KeychainService.save(privateKeyKey,   value: privateKey.trimmingCharacters(in: .whitespacesAndNewlines))
        isConfigured = true
    }

    func disconnect() {
        KeychainService.delete(keyIDKey)
        KeychainService.delete(issuerIDKey)
        KeychainService.delete(vendorNumberKey)
        KeychainService.delete(privateKeyKey)
        isConfigured = false
        summary = AppStoreDownloadSummary()
        error = nil
    }

    // MARK: - Load

    func loadDownloads() async {
        guard isConfigured, !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        guard let keyID        = KeychainService.load(keyIDKey),
              let issuerID     = KeychainService.load(issuerIDKey),
              let vendorNumber = KeychainService.load(vendorNumberKey),
              let privateKeyPEM = KeychainService.load(privateKeyKey) else {
            error = "Missing App Store Connect credentials."
            return
        }

        do {
            let jwt = try Self.generateJWT(keyID: keyID,
                                           issuerID: issuerID,
                                           privateKeyPEM: privateKeyPEM)

            let calendar = Calendar(identifier: .gregorian)
            let today    = Date()
            let dates    = (1...30).compactMap {
                calendar.date(byAdding: .day, value: -$0, to: today)
            }

            // Fetch all 30 daily reports concurrently.
            // Each addTask closure calls a nonisolated static method that only
            // does URLSession I/O, so they run in parallel even from MainActor.
            var allRows: [SalesReportRow] = []
            await withTaskGroup(of: [SalesReportRow].self) { group in
                for date in dates {
                    group.addTask {
                        do {
                            return try await Self.fetchReport(date: date,
                                                              vendorNumber: vendorNumber,
                                                              token: jwt)
                        } catch {
                            AppLogger.error(
                                "Report fetch failed for \(Self.reportDateFormatter.string(from: date)): \(error.localizedDescription)",
                                tag: "AppStore"
                            )
                            return []
                        }
                    }
                }
                for await rows in group {
                    allRows.append(contentsOf: rows)
                }
            }

            summary = Self.aggregate(allRows)
            AppLogger.log(
                "App Store: \(summary.totalDownloads) downloads across \(summary.appBreakdowns.count) apps (last 30 days)",
                tag: "AppStore"
            )
        } catch {
            self.error = error.localizedDescription
            AppLogger.error("AppStore load failed: \(error.localizedDescription)", tag: "AppStore")
        }
    }

    // MARK: - JWT (ES256)

    static func generateJWT(keyID: String, issuerID: String, privateKeyPEM: String) throws -> String {
        let now = Int(Date().timeIntervalSince1970)

        let header:  [String: Any] = ["alg": "ES256", "kid": keyID, "typ": "JWT"]
        let payload: [String: Any] = [
            "iss": issuerID,
            "iat": now,
            "exp": now + 1200,         // 20 min max allowed by Apple
            "aud": "appstoreconnect-v1"
        ]

        let headerB64  = try base64URLEncode(JSONSerialization.data(withJSONObject: header))
        let payloadB64 = try base64URLEncode(JSONSerialization.data(withJSONObject: payload))
        let signingInput = "\(headerB64).\(payloadB64)"

        let privateKey = try importP256PrivateKey(pem: privateKeyPEM)

        // CryptoKit returns DER-encoded ECDSA signature; JWT requires raw (r||s) P1363 format.
        let signature = try privateKey.signature(for: Data(signingInput.utf8))
        let sigB64 = base64URLEncode(signature.rawRepresentation)

        return "\(signingInput).\(sigB64)"
    }

    // MARK: - Report fetch

    private static func fetchReport(date: Date,
                                    vendorNumber: String,
                                    token: String) async throws -> [SalesReportRow] {
        let dateStr = reportDateFormatter.string(from: date)

        var components = URLComponents(string: "https://api.appstoreconnect.apple.com/v1/salesReports")!
        components.queryItems = [
            URLQueryItem(name: "filter[reportType]",    value: "SALES"),
            URLQueryItem(name: "filter[reportSubType]", value: "SUMMARY"),
            URLQueryItem(name: "filter[frequency]",     value: "DAILY"),
            URLQueryItem(name: "filter[vendorNumber]",  value: vendorNumber),
            URLQueryItem(name: "filter[reportDate]",    value: dateStr)
        ]
        guard let url = components.url else { throw AppStoreError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/a-gzip", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppStoreError.invalidResponse }

        switch http.statusCode {
        case 200:
            break
        case 404:
            AppLogger.log("No report for \(dateStr)", tag: "AppStore")
            return []
        default:
            let body = String(data: data, encoding: .utf8) ?? "no body"
            AppLogger.error("HTTP \(http.statusCode) for \(dateStr): \(body)", tag: "AppStore")
            throw AppStoreError.apiError(http.statusCode, body)
        }

        guard !data.isEmpty else { return [] }

        let decompressed = try data.gunzipped()
        return parseTSV(decompressed, date: date)
    }

    // MARK: - TSV parsing

    private static func parseTSV(_ data: Data, date: Date) -> [SalesReportRow] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var lines = text.components(separatedBy: "\n")
        guard !lines.isEmpty else { return [] }

        let headers = lines.removeFirst().components(separatedBy: "\t")

        // Column indices with Apple-documented fallback positions.
        let titleIdx       = headers.firstIndex(of: "Title")                   ?? 4
        let unitsIdx       = headers.firstIndex(of: "Units")                   ?? 7
        let proceedsIdx    = headers.firstIndex(of: "Developer Proceeds")      ?? 8
        let countryIdx     = headers.firstIndex(of: "Country Code")            ?? 12
        let productTypeIdx = headers.firstIndex(of: "Product Type Identifier") ?? 6
        let minimumColumnCount = max(titleIdx, unitsIdx, proceedsIdx, countryIdx, productTypeIdx) + 1

        return lines.compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return nil }
            let cols = line.components(separatedBy: "\t")
            guard cols.count >= minimumColumnCount else { return nil }
            let units = Int(cols[unitsIdx]) ?? 0
            // Include negative units (refunds) so totals stay accurate.
            guard units != 0 else { return nil }
            return SalesReportRow(
                title:       cols[titleIdx],
                units:       units,
                proceeds:    Double(cols[proceedsIdx]) ?? 0,
                countryCode: cols[countryIdx],
                productType: cols[productTypeIdx],
                date:        date
            )
        }
    }

    // MARK: - Aggregation

    private static func aggregate(_ rows: [SalesReportRow]) -> AppStoreDownloadSummary {
        var totalDownloads = 0
        var totalProceeds  = 0.0
        var byApp:  [String: (downloads: Int, proceeds: Double)] = [:]
        var byDate: [Date:   (downloads: Int, proceeds: Double)] = [:]
        let cal = Calendar(identifier: .gregorian)

        for row in rows {
            totalDownloads += row.units
            totalProceeds  += row.proceeds

            let currentApp = byApp[row.title] ?? (0, 0)
            byApp[row.title] = (currentApp.downloads + row.units, currentApp.proceeds + row.proceeds)

            let dayStart = cal.startOfDay(for: row.date)
            let currentDay = byDate[dayStart] ?? (0, 0)
            byDate[dayStart] = (currentDay.downloads + row.units, currentDay.proceeds + row.proceeds)
        }

        let appBreakdowns = byApp
            .map { AppDownloadBreakdown(appTitle: $0.key, downloads: $0.value.downloads, proceeds: $0.value.proceeds) }
            .sorted { $0.downloads > $1.downloads }

        let dailyDownloads = byDate
            .map { DailyDownload(date: $0.key, downloads: $0.value.downloads, proceeds: $0.value.proceeds) }
            .sorted { $0.date < $1.date }

        return AppStoreDownloadSummary(
            totalDownloads: totalDownloads,
            totalProceeds:  totalProceeds,
            appBreakdowns:  appBreakdowns,
            dailyDownloads: dailyDownloads
        )
    }

    // MARK: - Key import

    private static func importP256PrivateKey(pem: String) throws -> P256.Signing.PrivateKey {
        let stripped = pem
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespaces)

        guard let keyData = Data(base64Encoded: stripped) else {
            throw AppStoreError.invalidPrivateKey
        }

        do {
            return try P256.Signing.PrivateKey(derRepresentation: keyData)
        } catch {
            throw AppStoreError.keyImportFailed(error.localizedDescription)
        }
    }

    // MARK: - Base64URL helpers

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLEncode(_ string: String) throws -> String {
        guard let data = string.data(using: .utf8) else { throw AppStoreError.encodingFailed }
        return base64URLEncode(data)
    }
}

// MARK: - Gzip decompression (no third-party dependencies)

extension Data {
    /// Decompress gzip-encoded data using the Compression framework's raw DEFLATE decoder.
    func gunzipped() throws -> Data {
        // Not gzip? Return as-is (e.g. plain-text response on non-gzip day).
        guard count >= 18, self[0] == 0x1f, self[1] == 0x8b else { return self }

        let flags = self[3]
        var offset = 10

        // Skip optional FEXTRA field
        if flags & 0x04 != 0 {
            guard offset + 2 <= count else { throw AppStoreError.decompressionFailed }
            let xlen = Int(self[offset]) | (Int(self[offset + 1]) << 8)
            offset += 2 + xlen
        }
        // Skip optional FNAME (null-terminated)
        if flags & 0x08 != 0 {
            while offset < count && self[offset] != 0 { offset += 1 }
            guard offset < count else { throw AppStoreError.decompressionFailed }
            offset += 1
        }
        // Skip optional FCOMMENT (null-terminated)
        if flags & 0x10 != 0 {
            while offset < count && self[offset] != 0 { offset += 1 }
            guard offset < count else { throw AppStoreError.decompressionFailed }
            offset += 1
        }
        // Skip optional FHCRC (2 bytes)
        if flags & 0x02 != 0 { offset += 2 }

        // Deflate payload sits between `offset` and the 8-byte gzip trailer.
        guard offset + 8 < count else { throw AppStoreError.decompressionFailed }
        let compressed = self.subdata(in: offset ..< count - 8)

        // Generous output estimate: 10× compressed size, minimum 64 KB.
        let outputSize = max(compressed.count * 10, 65_536)
        var output = Data(count: outputSize)

        let written = compressed.withUnsafeBytes { src -> Int in
            output.withUnsafeMutableBytes { dst in
                compression_decode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, outputSize,
                    src.bindMemory(to: UInt8.self).baseAddress!, compressed.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { throw AppStoreError.decompressionFailed }
        return output.prefix(written)
    }
}

// MARK: - Errors

enum AppStoreError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(Int, String)
    case invalidPrivateKey
    case keyImportFailed(String)
    case encodingFailed
    case decompressionFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:              return "Invalid API URL."
        case .invalidResponse:         return "Invalid server response."
        case .apiError(let c, let m):  return "API error \(c): \(m)"
        case .invalidPrivateKey:       return "Could not decode .p8 private key."
        case .keyImportFailed(let m):  return "Key import failed: \(m)"
        case .encodingFailed:          return "UTF-8 encoding failed."
        case .decompressionFailed:     return "Failed to decompress report data."
        }
    }
}
