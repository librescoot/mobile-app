import SwiftUI
import WidgetKit

struct ScooterEntry: TimelineEntry {
    let date: Date
    let snapshot: CompanionSnapshot?
}

struct ScooterProvider: TimelineProvider {
    private func entry() -> ScooterEntry {
        let defaults = UserDefaults(suiteName: WatchCache.group) ?? .standard
        return ScooterEntry(date: Date(), snapshot: WatchCache.selected(defaults: defaults)?.snapshot)
    }
    func placeholder(in context: Context) -> ScooterEntry { ScooterEntry(date: Date(), snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (ScooterEntry) -> Void) { completion(entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ScooterEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .never))
    }
}

struct ScooterComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScooterEntry
    private var range: String { entry.snapshot?.rangeKm.map { "≈\($0)" } ?? "—" }
    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Text("Scooter \(range) km · cached")
            case .accessoryCircular:
                VStack { Text(range).font(.headline); Text("km cached").font(.caption2) }
            default:
                VStack(alignment: .leading) {
                    Text(entry.snapshot?.name ?? "Librescoot").font(.headline)
                    Text("\(range) km · last known")
                    if let updated = entry.snapshot?.updatedAt {
                        Text(Date(timeIntervalSince1970: Double(updated) / 1000), style: .relative).font(.caption2)
                    } else { Text("Open to connect").font(.caption2) }
                }
            }
        }
        .containerBackground(.black, for: .widget)
        .widgetURL(URL(string: "librescoot-watch://controls"))
        .privacySensitive()
    }
}

@main
struct ScooterWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ScooterWatchStatus", provider: ScooterProvider()) { entry in
            ScooterComplicationView(entry: entry)
        }
        .configurationDisplayName("Scooter range")
        .description("Last-known range. Open the app for scooter controls.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
