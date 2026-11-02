import AppIntents
import SwiftUI
import WidgetKit

@main
struct LampWidgetBundle: WidgetBundle {
    var body: some Widget {
        LampWidget()
        LampOnControl()
        LampOffControl()
    }
}

// MARK: - Home Screen widget

struct LampEntry: TimelineEntry {
    let date: Date
}

struct LampProvider: TimelineProvider {
    func placeholder(in context: Context) -> LampEntry { LampEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (LampEntry) -> Void) {
        completion(LampEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LampEntry>) -> Void) {
        // Nothing changes over time; the widget is just two buttons.
        completion(Timeline(entries: [LampEntry(date: .now)], policy: .never))
    }
}

struct LampWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let buttons = Group {
            Button(intent: TurnLampOnIntent()) {
                Label("On", systemImage: "lightbulb.max.fill")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .tint(.orange)

            Button(intent: TurnLampOffIntent()) {
                Label("Off", systemImage: "lightbulb.slash")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .tint(.gray)
        }
        .buttonStyle(.borderedProminent)
        .font(.headline)

        VStack(alignment: .leading, spacing: 8) {
            Label("Lamp", systemImage: "lightbulb.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if family == .systemSmall {
                VStack(spacing: 8) { buttons }
            } else {
                HStack(spacing: 10) { buttons }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct LampWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LampWidget", provider: LampProvider()) { _ in
            LampWidgetView()
        }
        .configurationDisplayName("Lamp")
        .description("Turn your Triones bulb on or off.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Control Center / Lock Screen / Action button controls

struct LampOnControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LampOnControl") {
            ControlWidgetButton(action: TurnLampOnIntent()) {
                Label("Lamp On", systemImage: "lightbulb.max.fill")
            }
        }
        .displayName("Lamp On")
        .description("Turn the lamp on.")
    }
}

struct LampOffControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LampOffControl") {
            ControlWidgetButton(action: TurnLampOffIntent()) {
                Label("Lamp Off", systemImage: "lightbulb.slash")
            }
        }
        .displayName("Lamp Off")
        .description("Turn the lamp off.")
    }
}
