import Foundation

// Sync flow: StorageOwner.local is the signed-out namespace that gets migrated
// into an account owner when the user signs in.
enum StorageOwner {
    nonisolated static let local = "local-device"
}

enum BackendIntegerContract {
    nonisolated static let min = Int(Int32.min)
    nonisolated static let max = Int(Int32.max)
    nonisolated static let userFacingMax = "2,147,483,647"
    nonisolated static let userFacingNonNegativeRange = "0 to 2,147,483,647"

    nonisolated static func clampedNonNegative(_ value: Int) -> Int {
        Swift.min(Swift.max(value, 0), max)
    }

    nonisolated static func clampedNonNegative(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        if value >= Double(max) { return max }
        if value <= 0 { return 0 }
        return Int(value.rounded())
    }

    nonisolated static func validateSigned(_ value: Int, fieldName: String) throws {
        guard (min...max).contains(value) else {
            throw BackendIntegerContractError.outOfRange(
                fieldName: fieldName,
                value: value,
                lowerBound: min,
                upperBound: max
            )
        }
    }

    nonisolated static func validateNonNegative(_ value: Int, fieldName: String) throws {
        guard (0...max).contains(value) else {
            throw BackendIntegerContractError.outOfRange(
                fieldName: fieldName,
                value: value,
                lowerBound: 0,
                upperBound: max
            )
        }
    }

    nonisolated static func validatePositive(_ value: Int, fieldName: String) throws {
        guard (1...max).contains(value) else {
            throw BackendIntegerContractError.outOfRange(
                fieldName: fieldName,
                value: value,
                lowerBound: 1,
                upperBound: max
            )
        }
    }

    nonisolated static func sqliteSignedCheck(_ column: String) -> String {
        "CHECK (\(column) BETWEEN \(min) AND \(max))"
    }

    nonisolated static func sqliteOptionalSignedCheck(_ column: String) -> String {
        "CHECK (\(column) IS NULL OR \(column) BETWEEN \(min) AND \(max))"
    }

    nonisolated static func sqliteNonNegativeCheck(_ column: String) -> String {
        "CHECK (\(column) BETWEEN 0 AND \(max))"
    }

    nonisolated static func sqlitePositiveCheck(_ column: String) -> String {
        "CHECK (\(column) BETWEEN 1 AND \(max))"
    }
}

enum BackendIntegerContractError: Error, LocalizedError {
    case outOfRange(fieldName: String, value: Int, lowerBound: Int, upperBound: Int)

    var errorDescription: String? {
        switch self {
        case .outOfRange(let fieldName, let value, let lowerBound, let upperBound):
            return "\(fieldName) must be between \(lowerBound) and \(upperBound). You sent \(value)."
        }
    }
}

enum AppDateCoding {
    private static let backendCalendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    private static let backendFormatterWithoutFractionalSeconds: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
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

            if let date = parseBackendNaiveTimestamp(rawValue) {
                return date
            }

            if let date = backendFormatterWithoutFractionalSeconds.date(from: rawValue) {
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
    // without a timezone suffix when talking to `/api/v1/sync`.
    static func backendTimestamp(from date: Date) -> String {
        var wholeSeconds = Int64(floor(date.timeIntervalSince1970))
        var microseconds = Int64(((date.timeIntervalSince1970 - Double(wholeSeconds)) * 1_000_000).rounded())
        if microseconds == 1_000_000 {
            wholeSeconds += 1
            microseconds = 0
        }

        let components = backendCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date(timeIntervalSince1970: Double(wholeSeconds))
        )

        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.%06d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0,
            microseconds
        )
    }

    static func parseBackendTimestamp(_ rawValue: String?) -> Date? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        return parseBackendNaiveTimestamp(rawValue)
            ?? backendFormatterWithoutFractionalSeconds.date(from: rawValue)
            ?? isoFormatterWithFractionalSeconds.date(from: rawValue)
            ?? isoFormatter.date(from: rawValue)
    }

    private static func parseBackendNaiveTimestamp(_ rawValue: String) -> Date? {
        guard rawValue.count >= 19 else { return nil }
        guard rawValue[rawValue.index(rawValue.startIndex, offsetBy: 4)] == "-",
              rawValue[rawValue.index(rawValue.startIndex, offsetBy: 7)] == "-",
              rawValue[rawValue.index(rawValue.startIndex, offsetBy: 10)] == "T",
              rawValue[rawValue.index(rawValue.startIndex, offsetBy: 13)] == ":",
              rawValue[rawValue.index(rawValue.startIndex, offsetBy: 16)] == ":" else {
            return nil
        }

        func int(_ lower: Int, _ upper: Int) -> Int? {
            let start = rawValue.index(rawValue.startIndex, offsetBy: lower)
            let end = rawValue.index(rawValue.startIndex, offsetBy: upper)
            return Int(rawValue[start..<end])
        }

        guard let year = int(0, 4),
              let month = int(5, 7),
              let day = int(8, 10),
              let hour = int(11, 13),
              let minute = int(14, 16),
              let second = int(17, 19) else {
            return nil
        }

        var microseconds = 0
        if rawValue.count > 19 {
            let dotIndex = rawValue.index(rawValue.startIndex, offsetBy: 19)
            guard rawValue[dotIndex] == "." else { return nil }
            let fractionStart = rawValue.index(after: dotIndex)
            let fraction = String(rawValue[fractionStart...])
            guard !fraction.isEmpty,
                  fraction.count <= 6,
                  fraction.allSatisfy(\.isNumber) else {
                return nil
            }
            microseconds = Int(fraction.padding(toLength: 6, withPad: "0", startingAt: 0)) ?? 0
        }

        var components = DateComponents()
        components.calendar = backendCalendar
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.nanosecond = microseconds * 1_000
        return backendCalendar.date(from: components)
    }
}

enum AppStorageLocation {
    private static func baseDirectory() -> URL {
        let baseDirectory =
            AppRuntimeEnvironment.storageDirectoryURL
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("bochi", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true, attributes: nil)
        return baseDirectory
    }

    static func fileURL(filename: String) -> URL {
        baseDirectory().appendingPathComponent("\(filename).json")
    }

    static func databaseURL(filename: String = "bochi") -> URL {
        baseDirectory().appendingPathComponent("\(filename).sqlite")
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
