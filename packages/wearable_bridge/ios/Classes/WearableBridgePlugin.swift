import Flutter
import WatchConnectivity

public final class WearableBridgePlugin: NSObject, FlutterPlugin {
    private let owner = UUID().uuidString
    private let channel: FlutterMethodChannel

    private init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
    }
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "org.librescoot.mobile/companion", binaryMessenger: registrar.messenger())
        let plugin = WearableBridgePlugin(channel: channel)
        registrar.addMethodCallDelegate(plugin, channel: channel)
        PhoneCompanion.shared.activate()
    }
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "snapshot":
            if let snapshot = call.arguments as? [String: Any] {
                PhoneCompanion.shared.publish(owner, channel: channel, snapshot: snapshot.filter { !($0.value is NSNull) })
            }
            result(nil)
        case "detach":
            PhoneCompanion.shared.detach(owner)
            result(nil)
        default: result(FlutterMethodNotImplemented)
        }
    }
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        PhoneCompanion.shared.detach(owner)
    }
}

private final class PhoneCompanion: NSObject, WCSessionDelegate {
    static let shared = PhoneCompanion()
    private struct Owner {
        let channel: FlutterMethodChannel
        let snapshot: [String: Any]
    }
    private var owners: [String: Owner] = [:]
    private var busy = false

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    func publish(_ id: String, channel: FlutterMethodChannel, snapshot: [String: Any]) {
        owners[id] = Owner(channel: channel, snapshot: snapshot)
        if snapshot["connected"] as? Bool == true || !owners.values.contains(where: { $0.snapshot["connected"] as? Bool == true }) {
            try? WCSession.default.updateApplicationContext(["snapshot": snapshot])
        }
    }
    func detach(_ id: String) { owners.removeValue(forKey: id) }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async {
            let id = message["id"] as? String ?? ""
            let scooterId = message["scooterId"] as? String ?? ""
            func reply(_ status: String) {
                replyHandler(["version": 1, "id": id, "scooterId": scooterId, "status": status])
            }
            guard message["version"] as? Int == 1,
                  id.range(of: "^[a-zA-Z0-9-]{16,64}$", options: .regularExpression) != nil,
                  !scooterId.isEmpty, scooterId.count <= 128,
                  let action = message["action"] as? String,
                  ["refresh", "lock", "unlock", "openSeat"].contains(action),
                  let issued = message["issuedAt"] as? Int,
                  let expires = message["expiresAt"] as? Int,
                  expires > issued, expires - issued <= 15000 else { reply("invalid"); return }
            let now = Int(Date().timeIntervalSince1970 * 1000)
            guard issued <= now + 2000, expires > now else { reply("expired"); return }
            let defaults = UserDefaults.standard
            var seen = defaults.dictionary(forKey: "companion.requests") as? [String: Int] ?? [:]
            guard seen[id] == nil else { reply("duplicate"); return }
            seen = seen.filter { $0.value > now }
            seen[id] = expires
            defaults.set(seen, forKey: "companion.requests")
            defaults.synchronize()
            guard !self.busy else { reply("busy"); return }
            guard let owner = self.owners.values.first(where: {
                $0.snapshot["connected"] as? Bool == true && $0.snapshot["scooterId"] as? String == scooterId
            }) else { reply("unavailable"); return }
            self.busy = true
            var finished = false
            func finish(_ status: String) {
                guard !finished else { return }
                finished = true
                self.busy = false
                reply(status)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(expires - now) / 1000) { finish("unknown") }
            owner.channel.invokeMethod("command", arguments: message) { result in
                finish(result as? String ?? "unknown")
            }
        }
    }
}
