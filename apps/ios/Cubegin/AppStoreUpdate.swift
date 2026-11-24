import Foundation
import StoreKit

enum AppStoreUpdate {
    static var installedVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private static let bundleID = "io.github.deweyou.cubegin"

    struct Release: Decodable, Equatable {
        let bundleId: String
        let version: String
        let minimumOsVersion: String
        let releaseNotes: String?
        let trackViewUrl: URL
    }

    enum Outcome: Equatable {
        case upToDate
        case available(Release)
        case requiresNewerOS(Release)
        case unavailable
        case testFlight
        case failed
    }

    private struct LookupResponse: Decodable {
        let results: [Release]
    }

    static func check() async throws -> Outcome {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-cubegin-preview-app-update"),
           let url = URL(string: "https://apps.apple.com/") {
            return .available(Release(
                bundleId: bundleID,
                version: "0.2.0",
                minimumOsVersion: "26.0",
                releaseNotes: "Improved timer gestures and added more options for importing results.",
                trackViewUrl: url
            ))
        }
#else
        if case .verified(let transaction) = try? await AppTransaction.shared, transaction.environment == .sandbox {
            return .testFlight
        }
#endif
        guard let installedVersion else { return .failed }
        let storefront = await Storefront.current
        // StoreKit uses ISO alpha-3, and Lookup expects alpha-2.
        // Fall back to the device region when StoreKit provides no recognized storefront.
        guard let country = lookupCountry(storefront?.countryCode) ?? Locale.current.region?.identifier,
              country.count == 2 else { return .failed }

        let appID = Bundle.main.object(forInfoDictionaryKey: "CubeginAppStoreID") as? String
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/lookup"
        components.queryItems = [
            appID.flatMap { Int($0) }.map { URLQueryItem(name: "id", value: String($0)) }
                ?? URLQueryItem(name: "bundleId", value: bundleID),
            URLQueryItem(name: "country", value: country.lowercased())
        ]
        guard let url = components.url else { return .failed }

        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return .failed }

        let os = ProcessInfo.processInfo.operatingSystemVersion
        return try evaluate(data, installedVersion: installedVersion, osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
    }

    static func evaluate(_ data: Data, installedVersion: String, osVersion: String) throws -> Outcome {
        let response = try JSONDecoder().decode(LookupResponse.self, from: data)
        guard let release = response.results.first(where: { $0.bundleId == bundleID }) else { return .unavailable }
        guard let installedOrder = compareVersions(release.version, installedVersion) else { return .failed }
        guard installedOrder == .orderedDescending else { return .upToDate }
        guard let osOrder = compareVersions(release.minimumOsVersion, osVersion),
              release.trackViewUrl.scheme == "https", release.trackViewUrl.host == "apps.apple.com" else { return .failed }
        return osOrder == .orderedDescending ? .requiresNewerOS(release) : .available(release)
    }

    static func lookupCountry(_ storefrontCountry: String?) -> String? {
        guard let storefrontCountry else { return nil }
        let locale = Locale(identifier: "en_US_POSIX")
        guard let name = locale.localizedString(forRegionCode: storefrontCountry) else { return nil }
        let matches = Locale.Region.isoRegions.filter {
            $0.identifier.count == 2 && locale.localizedString(forRegionCode: $0.identifier) == name
        }
        return matches.count == 1 ? matches.first?.identifier : nil
    }

    private static func compareVersions(_ left: String, _ right: String) -> ComparisonResult? {
        func parts(_ version: String) -> [Int]? {
            let fields = version.split(separator: ".", omittingEmptySubsequences: false)
            let numbers = fields.compactMap { Int($0) }
            guard numbers.count == fields.count, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
            return numbers
        }

        guard let lhs = parts(left), let rhs = parts(right) else { return nil }
        for index in 0..<max(lhs.count, rhs.count) {
            let leftPart = index < lhs.count ? lhs[index] : 0
            let rightPart = index < rhs.count ? rhs[index] : 0
            if leftPart != rightPart {
                return leftPart < rightPart ? .orderedAscending : .orderedDescending
            }
        }
        return .orderedSame
    }
}
