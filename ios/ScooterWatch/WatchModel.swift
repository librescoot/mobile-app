import Combine
import Foundation
import WatchConnectivity
import WatchKit
import WidgetKit

@MainActor
final class WatchModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published var targets: [WatchTarget] = []
    @Published var selectedID: String = ""
    @Published var candidates: [WatchCandidate] = []
    @Published var busy = false
    @Published var message = "Choose a scooter or pair this watch."
    private let defaults = UserDefaults(suiteName: WatchCache.group) ?? .standard
    private var bluetooth: WatchBluetooth?
    private var relayID: String?
    var selected: WatchTarget? { targets.first { $0.id == selectedID } ?? targets.first }

    override init() {
        super.init()
        targets = WatchCache.targets(defaults: defaults)
        selectedID = defaults.string(forKey: "selected") ?? targets.first?.id ?? ""
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    func select(_ id: String) {
        guard !busy else { return }
        selectedID = id
        defaults.set(id, forKey: "selected")
        WidgetCenter.shared.reloadAllTimelines()
    }
    private func save(_ snapshot: CompanionSnapshot, route: String) {
        let target = WatchTarget(route: route, snapshot: snapshot)
        targets.removeAll { $0.id == target.id }
        targets.append(target)
        if targets.count > 20 { targets.removeFirst(targets.count - 20) }
        if selectedID.isEmpty { select(target.id) }
        WatchCache.save(targets, defaults: defaults)
        WidgetCenter.shared.reloadAllTimelines()
    }
    func forget(_ id: String) {
        guard !busy else { return }
        targets.removeAll { $0.id == id }
        if selectedID == id { select(targets.first?.id ?? "") }
        WatchCache.save(targets, defaults: defaults)
        WidgetCenter.shared.reloadAllTimelines()
    }
    func scan() {
        guard !busy else { return }
        busy = true
        message = "Scanning…"
        candidates = []
        let ble = WatchBluetooth()
        bluetooth = ble
        ble.scan { [weak self] candidates in
            guard let self else { return }
            self.candidates = candidates
            self.busy = false
            self.message = candidates.isEmpty ? "No scooters found. Check pairing mode and Bluetooth permission." : "Select the scooter to pair."
            self.bluetooth = nil
        }
    }
    func pair(_ candidate: WatchCandidate) {
        guard !busy else { return }
        runDirect(id: candidate.id, name: candidate.name, action: .refresh, pairing: true)
    }
    func execute(_ action: CompanionAction) {
        guard !busy, let target = selected else { return }
        if target.route == "direct" {
            guard let id = UUID(uuidString: target.snapshot.scooterId) else { message = "Invalid scooter identity."; return }
            runDirect(id: id, name: target.snapshot.name, action: action, pairing: false)
        } else { runRelay(target, action: action) }
    }
    private func complete(_ status: String) {
        busy = false
        message = companionResultText(status)
        if status == "confirmed" { WKInterfaceDevice.current().play(.success) }
    }
    private func runDirect(id: UUID, name: String, action: CompanionAction, pairing: Bool) {
        busy = true
        message = pairing ? "Pairing — check the system PIN prompt…" : "Connecting…"
        let ble = WatchBluetooth()
        bluetooth = ble
        ble.execute(id: id, name: name, action: action, pairing: pairing, publish: { [weak self] snapshot in
            self?.save(snapshot, route: "direct")
            if pairing {
                self?.selectedID = "direct:\(snapshot.scooterId)"
                self?.defaults.set("direct:\(snapshot.scooterId)", forKey: "selected")
                WidgetCenter.shared.reloadAllTimelines()
            }
        }, completion: { [weak self] status in
            self?.bluetooth = nil
            self?.complete(status)
        })
    }
    private func runRelay(_ target: WatchTarget, action: CompanionAction) {
        guard WCSession.default.activationState == .activated, WCSession.default.isReachable else {
            message = "Phone unavailable. Open the phone app and connect it to the scooter, or use a paired direct BLE key."
            return
        }
        let request = CompanionRequest(scooterId: target.snapshot.scooterId, action: action)
        busy = true
        relayID = request.id
        message = "Waiting for phone…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 16) { [weak self] in
            guard let self, self.relayID == request.id else { return }
            self.relayID = nil
            self.complete("unknown")
        }
        WCSession.default.sendMessage(request.dictionary, replyHandler: { [weak self] response in
            DispatchQueue.main.async {
                guard let self, self.relayID == request.id,
                      response["version"] as? Int == 1, response["id"] as? String == request.id,
                      response["scooterId"] as? String == request.scooterId else { return }
                self.relayID = nil
                self.complete(response["status"] as? String ?? "unknown")
            }
        }, errorHandler: { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.relayID == request.id else { return }
                self.relayID = nil
                self.complete("unknown")
            }
        })
    }
    private func receive(_ context: [String: Any]) {
        guard let dictionary = context["snapshot"] as? [String: Any],
              let snapshot = try? CompanionSnapshot(dictionary: dictionary) else { return }
        save(snapshot, route: "phone")
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { [weak self] in self?.receive(session.receivedApplicationContext) }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.receive(applicationContext) }
    }
}
