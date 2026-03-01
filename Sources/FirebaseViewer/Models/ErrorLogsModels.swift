import Foundation

// MARK: - Cloud Logging API Models

struct ErrorLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let severity: String
    let message: String
    let resource: String
    let labels: [String: String]
    let insertId: String?

    var isGroqQuotaError: Bool {
        message.localizedCaseInsensitiveContains("groq") &&
        (message.localizedCaseInsensitiveContains("quota") ||
         message.localizedCaseInsensitiveContains("rate limit") ||
         message.localizedCaseInsensitiveContains("429"))
    }
}

// MARK: - Cloud Logging API Response

struct LogEntriesResponse: Decodable {
    let entries: [LogEntryRaw]?
    let nextPageToken: String?
}

struct LogEntryRaw: Decodable {
    let timestamp: String?
    let receiveTimestamp: String?
    let severity: String?
    let textPayload: String?
    let jsonPayload: [String: AnyCodable]?
    let resource: LogResource?
    let labels: [String: String]?
    let insertId: String?

    struct LogResource: Decodable {
        let type: String?
        let labels: [String: String]?
    }

    func toErrorLogEntry() -> ErrorLogEntry? {
        // Parse timestamp
        let timestampStr = timestamp ?? receiveTimestamp ?? ""
        let date = ISO8601DateFormatter().date(from: timestampStr) ?? Date()

        // Extract message
        var message = textPayload ?? ""
        if message.isEmpty, let json = jsonPayload {
            if let errorMessage = json["message"]?.value as? String {
                message = errorMessage
            } else if let errorMsg = json["error"]?.value as? String {
                message = errorMsg
            } else {
                message = json.description
            }
        }

        guard !message.isEmpty else { return nil }

        // Extract resource info
        var resourceStr = resource?.type ?? "unknown"
        if let resLabels = resource?.labels {
            let labelStr = resLabels.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            if !labelStr.isEmpty {
                resourceStr += " (\(labelStr))"
            }
        }

        return ErrorLogEntry(
            timestamp: date,
            severity: severity ?? "DEFAULT",
            message: message,
            resource: resourceStr,
            labels: labels ?? [:],
            insertId: insertId
        )
    }
}

// Helper to decode arbitrary JSON values
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array
        } else {
            value = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case let dict as [String: AnyCodable]:
            try container.encode(dict)
        case let array as [AnyCodable]:
            try container.encode(array)
        default:
            try container.encode("")
        }
    }
}
