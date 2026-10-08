import SwiftUI

@main
@MainActor
struct ScooterWatchApp: App {
    @StateObject private var model = WatchModel()
    var body: some Scene {
        WindowGroup { WatchControls(model: model) }
    }
}

@MainActor
struct WatchControls: View {
    @ObservedObject var model: WatchModel
    @State private var pending: CompanionAction?
    @State private var showConfirmation = false
    @State private var showPairing = false
    @State private var showRemove = false

    var body: some View {
        NavigationStack {
            List {
                if let target = model.selected {
                    let snapshot = target.snapshot
                    Text(snapshot.name).font(.headline)
                    Text(target.route == "direct" ? "Direct Bluetooth key" : "Via phone").font(.caption)
                    Text("Last state: \(snapshot.state ?? "unknown")")
                    Text("Batteries: \(battery(snapshot.battery1)) / \(battery(snapshot.battery2))")
                    if let range = snapshot.rangeKm { Text("≈\(range) km") }
                    if let updated = snapshot.updatedAt {
                        HStack {
                            Text("Updated")
                            Text(Date(timeIntervalSince1970: Double(updated) / 1000), style: .relative)
                        }.font(.caption2)
                    } else { Text("No recent telemetry").font(.caption2) }
                    ForEach(CompanionAction.allCases, id: \.rawValue) { action in
                        Button(action.title) {
                            if action == .refresh { model.execute(action) }
                            else { pending = action; showConfirmation = true }
                        }.disabled(model.busy)
                    }
                    if let lat = snapshot.latitude, let lon = snapshot.longitude,
                       let url = URL(string: "https://maps.apple.com/?ll=\(lat),\(lon)&q=Parked+scooter") {
                        Link("Parked location", destination: url)
                    }
                }
                if model.busy { ProgressView() }
                Text(model.message).font(.caption)
                NavigationLink("Choose scooter") {
                    List(model.targets) { target in
                        Button("\(target.snapshot.name) · \(target.route)") { model.select(target.id) }
                            .disabled(model.busy)
                    }
                }.disabled(model.busy)
                Button("Pair direct BLE key") { showPairing = true }.disabled(model.busy)
                if model.selected != nil {
                    Button("Remove from watch", role: .destructive) { showRemove = true }.disabled(model.busy)
                }
                Text("No passive unlocking or NFC key. Keep a backup key.").font(.caption2)
            }
            .navigationTitle("Librescoot")
        }
        .confirmationDialog(pending.map { "\($0.title)?" } ?? "Confirm", isPresented: $showConfirmation, titleVisibility: .visible) {
            Button("Confirm") { if let pending { model.execute(pending) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keep the scooter stationary. Unlock enables the vehicle; lock and seatbox controls require parked state.")
        }
        .confirmationDialog("Remove local shortcut?", isPresented: $showRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { if let selected = model.selected { model.forget(selected.id) } }
        } message: {
            Text("This does not revoke the BLE bond. Revoke a lost watch on the scooter and keep another working key.")
        }
        .sheet(isPresented: $showPairing) {
            NavigationStack {
                List {
                    Text("Park the scooter using an existing key. Disconnect the phone if it occupies the BLE connection. Enter the scooter's pairing PIN on this watch.").font(.caption)
                    Button("Scan nearby") { model.scan() }.disabled(model.busy)
                    if model.busy { ProgressView() }
                    Text(model.message).font(.caption)
                    ForEach(model.candidates) { candidate in
                        Button("\(candidate.name) · \(candidate.id.uuidString.suffix(6))") { model.pair(candidate) }.disabled(model.busy)
                    }
                    Button("Done") { showPairing = false }.disabled(model.busy)
                }.navigationTitle("Pair watch")
            }
        }
    }
    private func battery(_ value: Int?) -> String { value.map { "\($0)%" } ?? "—" }
}
