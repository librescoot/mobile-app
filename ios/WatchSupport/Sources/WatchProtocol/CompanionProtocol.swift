import Foundation

public enum CompanionAction: String, Codable, CaseIterable, Sendable {
    case refresh, lock, unlock, openSeat
    public var title: String {
        switch self {
        case .refresh: return "Refresh / connect"
        case .lock: return "Lock"
        case .unlock: return "Unlock"
        case .openSeat: return "Open seatbox"
        }
    }
    public var wire: String? {
        switch self {
        case .lock: return "scooter:state lock"
        case .unlock: return "scooter:state unlock"
        case .openSeat: return "scooter:seatbox open"
        case .refresh: return nil
        }
    }
    public func allows(_ state: String?) -> Bool {
        switch self {
        case .lock, .unlock: return state == "stand-by" || state == "parked"
        case .openSeat: return state == "parked"
        case .refresh: return true
        }
    }
    public func confirms(_ state: String?, seatClosed: Bool?) -> Bool {
        switch self {
        case .unlock: return state == "parked"
        case .lock: return state == "stand-by"
        case .openSeat: return seatClosed == false
        case .refresh: return state != nil
        }
    }
}

public struct CompanionRequest: Codable, Sendable {
    public let version: Int
    public let id: String
    public let scooterId: String
    public let action: CompanionAction
    public let issuedAt: Int64
    public let expiresAt: Int64
    public init(scooterId: String, action: CompanionAction, now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        version = 1
        id = UUID().uuidString
        self.scooterId = scooterId
        self.action = action
        issuedAt = now
        expiresAt = now + 15000
    }
    public var dictionary: [String: Any] {
        ["version": version, "id": id, "scooterId": scooterId, "action": action.rawValue,
         "issuedAt": issuedAt, "expiresAt": expiresAt]
    }
    public func valid(at now: Int64) -> Bool {
        version == 1 && !scooterId.isEmpty && scooterId.count <= 128 && UUID(uuidString: id) != nil &&
            issuedAt >= 0 && expiresAt > issuedAt && expiresAt - issuedAt <= 15000 && issuedAt <= now + 2000 && now < expiresAt
    }
}

public struct CompanionSnapshot: Codable, Sendable {
    public var version = 1
    public var scooterId: String
    public var name: String
    public var state: String?
    public var connected: Bool = false
    public var battery1: Int?
    public var battery2: Int?
    public var rangeKm: Int?
    public var seatClosed: Bool?
    public var updatedAt: Int64?
    public var latitude: Double?
    public var longitude: Double?
    public init(scooterId: String, name: String) { self.scooterId = scooterId; self.name = name }
    public init(dictionary: [String: Any]) throws {
        self = try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: dictionary))
        guard version == 1, !scooterId.isEmpty, scooterId.count <= 128 else { throw ProtocolError.invalid }
        battery1 = battery1.flatMap { (0...100).contains($0) ? $0 : nil }
        battery2 = battery2.flatMap { (0...100).contains($0) ? $0 : nil }
        rangeKm = Self.range(battery1, battery2)
    }
    public static func range(_ first: Int?, _ second: Int?) -> Int? {
        guard first != nil || second != nil else { return nil }
        return Int((Double((first ?? 0) + (second ?? 0)) * 0.45).rounded())
    }
    public static func text(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0 \n\r"))
    }
    public static func uint32(_ data: Data) -> UInt32? {
        guard data.count == 4 else { return nil }
        return data.enumerated().reduce(0) { $0 | (UInt32($1.element) << ($1.offset * 8)) }
    }
}

public enum ProtocolError: Error { case invalid }

public struct WatchTarget: Codable, Identifiable, Sendable {
    public let route: String
    public var snapshot: CompanionSnapshot
    public var id: String { "\(route):\(snapshot.scooterId)" }
    public init(route: String, snapshot: CompanionSnapshot) { self.route = route; self.snapshot = snapshot }
}

public enum WatchCache {
    public static let group = "group.org.librescoot.mobile.unu.watch"
    public static func targets(defaults: UserDefaults) -> [WatchTarget] {
        guard let data = defaults.data(forKey: "targets") else { return [] }
        return (try? JSONDecoder().decode([WatchTarget].self, from: data)) ?? []
    }
    public static func selected(defaults: UserDefaults) -> WatchTarget? {
        let targets = targets(defaults: defaults)
        return targets.first { $0.id == defaults.string(forKey: "selected") } ?? targets.first
    }
    public static func save(_ targets: [WatchTarget], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(targets) else { return }
        defaults.set(data, forKey: "targets")
    }
}

public func companionResultText(_ status: String) -> String {
    switch status {
    case "confirmed": return "Confirmed by scooter"
    case "unknown": return "Outcome unknown. Check the scooter before trying again."
    case "unsafeState": return "Not allowed in this state. Park or wake the scooter first."
    case "phoneAuthRequired": return "Use authentication on your phone."
    case "expired": return "Request expired. Nothing further will be sent."
    case "duplicate": return "Request already handled. Refresh to check the scooter."
    case "busy": return "Another command is running."
    default: return "Unavailable. Connect your phone or move closer for direct Bluetooth."
    }
}
