import Foundation
import Testing
@testable import CubeginApp

struct AppStoreUpdateTests {
    @Test
    func comparesNumericVersionAndPreservesOptionalNotes() throws {
        let update = try AppStoreUpdate.evaluate(lookup(), installedVersion: "0.9.0", osVersion: "26.0.0")
        guard case .available(let release) = update else {
            Issue.record("Expected an available update")
            return
        }
        #expect(release.version == "0.10.0")
        #expect(release.releaseNotes == nil)
        #expect(release.trackViewUrl.host == "apps.apple.com")
    }

    @Test
    func distinguishesCurrentVersionAndOSRequirement() throws {
        let current = try AppStoreUpdate.evaluate(lookup(), installedVersion: "0.10", osVersion: "26.0")
        #expect(current == .upToDate)
        let ahead = try AppStoreUpdate.evaluate(lookup(), installedVersion: "1.0", osVersion: "26.0")
        #expect(ahead == .upToDate)
        let update = try AppStoreUpdate.evaluate(lookup(minimumOS: "26.2"), installedVersion: "0.9", osVersion: "26.1")
        guard case .requiresNewerOS(let release) = update else {
            Issue.record("Expected an OS requirement")
            return
        }
        #expect(release.minimumOsVersion == "26.2")
    }

    @Test
    func rejectsUnrelatedListingsAndInvalidVersions() throws {
        let unrelated = try AppStoreUpdate.evaluate(
            lookup(bundleID: "other.app"), installedVersion: "0.9", osVersion: "26"
        )
        #expect(unrelated == .unavailable)
        let invalid = try AppStoreUpdate.evaluate(lookup(version: "invalid"), installedVersion: "0.9", osVersion: "26")
        #expect(invalid == .failed)
    }

    @Test(arguments: [("CHN", "CN"), ("USA", "US"), ("GBR", "GB"), ("HKG", "HK")])
    func mapsStorefrontCountry(storefront: String, lookup: String) {
        #expect(AppStoreUpdate.lookupCountry(storefront) == lookup)
    }

    private func lookup(
        bundleID: String = "io.github.deweyou.cubegin",
        version: String = "0.10.0",
        minimumOS: String = "26.0"
    ) -> Data {
        Data("""
        {"results": [{
            "bundleId": "\(bundleID)",
            "version": "\(version)",
            "minimumOsVersion": "\(minimumOS)",
            "trackViewUrl": "https://apps.apple.com/us/app/cubegin/id123"
        }]}
        """.utf8)
    }
}
