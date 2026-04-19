import Foundation

enum StorageOwner {
    nonisolated static let local = "local-device"
}

enum AppDateCoding {
    private static let backendFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        return formatter
    }()

    private static let isoFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoFormatterWithFractionalSeconds.string(from: date))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)

            if let date = isoFormatterWithFractionalSeconds.date(from: rawValue) {
                return date
            }

            if let date = isoFormatter.date(from: rawValue) {
                return date
            }

            if let date = backendFormatter.date(from: rawValue) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported date value: \(rawValue)"
            )
        }
        return decoder
    }

    // The Rust backend uses `NaiveDateTime`, so Swift must serialize UTC values
    // without a timezone suffix when talking to `/api/sync`.
    static func backendTimestamp(from date: Date) -> String {
        backendFormatter.string(from: date)
    }

    static func parseBackendTimestamp(_ rawValue: String?) -> Date? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        return backendFormatter.date(from: rawValue)
            ?? isoFormatterWithFractionalSeconds.date(from: rawValue)
            ?? isoFormatter.date(from: rawValue)
    }
}

enum AppStorageLocation {
    static func fileURL(filename: String) -> URL {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tofustash", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true, attributes: nil)
        return baseDirectory.appendingPathComponent("\(filename).json")
    }
}

enum JSONFileStore {
    static func load<T: Decodable>(_ type: T.Type, from url: URL, defaultValue: @autoclosure () -> T) -> T {
        guard let data = try? Data(contentsOf: url) else {
            return defaultValue()
        }

        do {
            return try AppDateCoding.makeDecoder().decode(T.self, from: data)
        } catch {
            return defaultValue()
        }
    }

    static func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            let data = try AppDateCoding.makeEncoder().encode(value)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try data.write(to: url, options: .atomic)
        } catch {
            assertionFailure("Failed to persist JSON at \(url.lastPathComponent): \(error)")
        }
    }
}
