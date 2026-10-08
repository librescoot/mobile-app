import Foundation
import XCTest
@testable import WatchProtocol

final class CompanionProtocolTests: XCTestCase {
    func testCrossPlatformContract() throws {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let data = try Data(contentsOf: root.appendingPathComponent("test/fixtures/companion_contract.json"))
        let contract = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for item in try XCTUnwrap(contract["stateCases"] as? [[String: Any]]) {
            let action = try XCTUnwrap(CompanionAction(rawValue: item["action"] as? String ?? ""))
            XCTAssertEqual(action.allows(item["state"] as? String), item["allowed"] as? Bool)
            XCTAssertEqual(action.confirms(item["state"] as? String, seatClosed: item["seatClosed"] as? Bool), item["confirmed"] as? Bool)
        }
        for (name, wire) in try XCTUnwrap(contract["commands"] as? [String: String]) {
            XCTAssertEqual(CompanionAction(rawValue: name)?.wire, wire)
        }
    }
    func testBoundedTargetedRequest() throws {
        let request = CompanionRequest(scooterId: "a", action: .unlock, now: 100000)
        XCTAssertTrue(request.valid(at: 100000))
        XCTAssertFalse(request.valid(at: 115000))
        XCTAssertFalse(request.valid(at: 97000))
        XCTAssertEqual(request.dictionary["scooterId"] as? String, "a")
        XCTAssertEqual(request.dictionary["action"] as? String, "unlock")
        let decoded = try JSONDecoder().decode(CompanionRequest.self, from: JSONEncoder().encode(request))
        XCTAssertEqual(decoded.id, request.id)
    }
    func testConservativeStateGates() {
        for state in [nil, "ready-to-drive", "updating", "off", "unknown"] as [String?] {
            XCTAssertFalse(CompanionAction.unlock.allows(state))
            XCTAssertFalse(CompanionAction.lock.allows(state))
            XCTAssertFalse(CompanionAction.openSeat.allows(state))
        }
        XCTAssertTrue(CompanionAction.unlock.allows("stand-by"))
        XCTAssertTrue(CompanionAction.openSeat.allows("parked"))
        XCTAssertFalse(CompanionAction.openSeat.allows("stand-by"))
    }
    func testConfirmationIsNotHandlebarState() {
        XCTAssertTrue(CompanionAction.unlock.confirms("parked", seatClosed: true))
        XCTAssertFalse(CompanionAction.unlock.confirms("unlocked", seatClosed: true))
        XCTAssertFalse(CompanionAction.unlock.confirms("stand-by", seatClosed: true))
        XCTAssertTrue(CompanionAction.openSeat.confirms("parked", seatClosed: false))
        XCTAssertFalse(CompanionAction.openSeat.confirms("parked", seatClosed: nil))
    }
    func testWireAndTelemetry() {
        XCTAssertEqual(CompanionAction.lock.wire, "scooter:state lock")
        XCTAssertEqual(CompanionAction.unlock.wire, "scooter:state unlock")
        XCTAssertEqual(CompanionAction.openSeat.wire, "scooter:seatbox open")
        XCTAssertNil(CompanionAction.refresh.wire)
        XCTAssertNil(CompanionSnapshot.range(nil, nil))
        XCTAssertEqual(CompanionSnapshot.range(0, nil), 0)
        XCTAssertEqual(CompanionSnapshot.range(100, nil), 45)
        XCTAssertEqual(CompanionSnapshot.range(100, 100), 90)
        XCTAssertEqual(CompanionSnapshot.uint32(Data([100, 0, 0, 0])), 100)
        XCTAssertNil(CompanionSnapshot.uint32(Data([100])))
        XCTAssertEqual(CompanionSnapshot.text(Data("parked\0\0".utf8)), "parked")
    }
    func testNullablePhoneSnapshot() throws {
        let snapshot = try CompanionSnapshot(dictionary: ["version": 1, "scooterId": "a", "name": "Scooter",
            "state": "stand-by", "connected": false, "battery1": 50, "battery2": NSNull(), "updatedAt": 100000])
        XCTAssertEqual(snapshot.rangeKm, 23)
        XCTAssertNil(snapshot.battery2)
        XCTAssertThrowsError(try CompanionSnapshot(dictionary: ["version": 2, "scooterId": "a", "name": "Scooter", "connected": false]))
    }
    func testCachePreservesTransportIdentityAndSelection() {
        let suite = "watch-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let snapshot = CompanionSnapshot(scooterId: "a", name: "Scooter")
        WatchCache.save([WatchTarget(route: "phone", snapshot: snapshot), WatchTarget(route: "direct", snapshot: snapshot)], defaults: defaults)
        defaults.set("direct:a", forKey: "selected")
        XCTAssertEqual(WatchCache.targets(defaults: defaults).count, 2)
        XCTAssertEqual(WatchCache.selected(defaults: defaults)?.route, "direct")
    }
}
