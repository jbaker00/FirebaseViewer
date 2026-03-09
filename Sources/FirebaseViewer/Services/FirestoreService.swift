import Foundation

/// Fetches document-count statistics from Cloud Firestore using a service account.
struct FirestoreService {

    private static var cachedToken: String?
    private static var tokenExpiry: Date = .distantPast
    /// Seconds before a Google OAuth / service-account token is treated as expired.
    private static let tokenExpiryBuffer: TimeInterval = 3500

    // MARK: - Public

    static func fetchCollectionStats(projectID: String, serviceAccountJSON: String? = nil, accessToken: String? = nil) async throws -> [FirestoreCollectionStats] {
        let token = try await getToken(serviceAccountJSON: serviceAccountJSON, accessToken: accessToken)
        let collections = try await listCollections(projectID: projectID, token: token)
        return try await withThrowingTaskGroup(of: FirestoreCollectionStats.self) { group in
            for name in collections {
                group.addTask {
                    let count = try await countDocuments(projectID: projectID,
                                                         collection: name,
                                                         token: token)
                    return FirestoreCollectionStats(name: name, documentCount: count)
                }
            }
            var results: [FirestoreCollectionStats] = []
            for try await stat in group { results.append(stat) }
            return results.sorted { $0.documentCount > $1.documentCount }
        }
    }

    // MARK: - Private helpers

    private static func getToken(serviceAccountJSON: String?, accessToken: String? = nil) async throws -> String {
        // If a pre-fetched OAuth access token was provided (e.g., from Google Sign-In), use it directly.
        if let token = accessToken {
            cachedToken = token
            tokenExpiry = Date().addingTimeInterval(tokenExpiryBuffer)
            return token
        }
        if let t = cachedToken, Date() < tokenExpiry { return t }
        let t: String
        if let json = serviceAccountJSON {
            t = try await JWTService.accessToken(
                fromJSON: json,
                scope: "https://www.googleapis.com/auth/datastore"
            )
        } else {
            t = try await JWTService.accessToken(
                resource: "ResortViewerServiceAccount",
                scope: "https://www.googleapis.com/auth/datastore"
            )
        }
        cachedToken = t
        tokenExpiry = Date().addingTimeInterval(tokenExpiryBuffer)
        return t
    }

    private static func listCollections(projectID: String, token: String) async throws -> [String] {
        let url = URL(string: "https://firestore.googleapis.com/v1/projects/\(projectID)/databases/(default)/documents:listCollectionIds")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            AppLogger.error("Firestore listCollections HTTP \(http.statusCode): \(body)", tag: "Firestore")
            throw NSError(domain: "Firestore", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
        }
        AppLogger.log("Firestore listCollections OK", tag: "Firestore")
        struct Response: Decodable { let collectionIds: [String]? }
        return (try JSONDecoder().decode(Response.self, from: data)).collectionIds ?? []
    }

    private static func countDocuments(projectID: String, collection: String, token: String) async throws -> Int {
        let url = URL(string: "https://firestore.googleapis.com/v1/projects/\(projectID)/databases/(default)/documents:runAggregationQuery")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "structuredAggregationQuery": [
                "aggregations": [["alias": "count", "count": [:] as [String: Any]]],
                "structuredQuery": ["from": [["collectionId": collection]]]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: req)

        struct AggResult: Decodable {
            struct Result: Decodable {
                struct Fields: Decodable {
                    struct Val: Decodable { let integerValue: String? }
                    let count: Val?
                }
                let aggregateFields: Fields?
            }
            let result: Result?
        }
        let results = try JSONDecoder().decode([AggResult].self, from: data)
        let str = results.first?.result?.aggregateFields?.count?.integerValue ?? "0"
        return Int(str) ?? 0
    }
}
