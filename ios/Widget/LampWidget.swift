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

// MARK: - Timeline

struct LampEntry: TimelineEntry {
    let date: Date
}

struct LampProvider: TimelineProvider {
    func placeholder(in context: Context) -> LampEntry { LampEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (LampEntry) -> Void) {
        completion(LampEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LampEntry>) -> Void) {
        // The widget is a static remote control; nothing changes over time.
        completion(Timeline(entries: [LampEntry(date: .now)], policy: .never))
    }
}

// MARK: - Styling

private enum Palette {
    static let glow = LinearGradient(
        colors: [Color(red: 1.0, green: 0.82, blue: 0.35), Color(red: 1.0, green: 0.55, blue: 0.15)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let background = LinearGradient(
        colors: [Color(red: 0.20, green: 0.14, blue: 0.10), Color(red: 0.07, green: 0.06, blue: 0.08)],
        startPoint: .top,
        endPoint: .bottom
    )
    static let tile = Color.white.opacity(0.12)
}

// MARK: - Building blocks

private struct Header: View {
    var subtitle: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb.max.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.black.opacity(0.75))
                .frame(width: 26, height: 26)
                .background(Palette.glow, in: Circle())
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 0) {
                Text("Lamp")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct PowerTile: View {
    let isOn: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: isOn ? "lightbulb.max.fill" : "lightbulb.slash.fill")
                .font(.system(size: 22, weight: .semibold))
            Text(isOn ? "Turn On" : "Turn Off")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(isOn ? Color.black.opacity(0.8) : Color.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isOn ? AnyShapeStyle(Palette.glow) : AnyShapeStyle(Palette.tile))
        }
    }
}

private struct PowerButtons: View {
    var body: some View {
        Button(intent: TurnLampOnIntent()) { PowerTile(isOn: true) }
            .buttonStyle(.plain)
        Button(intent: TurnLampOffIntent()) { PowerTile(isOn: false) }
            .buttonStyle(.plain)
    }
}

private struct ColorDot: View {
    let preset: LampPreset
    var size: CGFloat = 30
    var showsName = true

    var body: some View {
        Button(intent: SetLampColorIntent(preset: preset)) {
            VStack(spacing: 3) {
                Circle()
                    .fill(preset.color.swiftUIColor.gradient)
                    .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                    .frame(width: size, height: size)
                    .shadow(color: preset.color.swiftUIColor.opacity(0.6), radius: 4)
                if showsName {
                    Text(preset.name)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private struct BrightnessButton: View {
    let percent: Int

    private var symbol: String {
        percent <= 25 ? "sun.min.fill" : "sun.max.fill"
    }

    var body: some View {
        Button(intent: SetLampBrightnessIntent(percent: percent)) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 10 + CGFloat(percent) / 10, weight: .semibold))
                    .foregroundStyle(Color(red: 1, green: 0.8, blue: 0.4).opacity(0.4 + Double(percent) / 170))
                    .frame(height: 22)
                Text("\(percent)%")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.tile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Layouts per size

struct LampWidgetView: View {
    @Environment(\.widgetFamily) private var family

    private let mediumPresets: [LampPreset] = [.warm, .red, .orange, .green, .blue, .purple]
    private let largePresets: [LampPreset] = [.warm, .red, .orange, .yellow, .green, .cyan, .blue, .purple]

    var body: some View {
        content
            .containerBackground(for: .widget) { Palette.background }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemMedium:
            HStack(spacing: 14) {
                VStack(spacing: 10) {
                    Header(subtitle: "Bluetooth")
                    HStack(spacing: 8) { PowerButtons() }
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 6) {
                    SectionLabel(text: "Colors")
                    Grid(horizontalSpacing: 4, verticalSpacing: 8) {
                        GridRow { ForEach(mediumPresets.prefix(3), id: \.self) { ColorDot(preset: $0, size: 28) } }
                        GridRow { ForEach(mediumPresets.suffix(3), id: \.self) { ColorDot(preset: $0, size: 28) } }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }

        case .systemLarge:
            VStack(spacing: 12) {
                Header(subtitle: "Triones Bluetooth bulb")
                HStack(spacing: 10) { PowerButtons() }
                    .frame(height: 84)

                SectionLabel(text: "Brightness")
                HStack(spacing: 8) {
                    ForEach([25, 50, 75, 100], id: \.self) { BrightnessButton(percent: $0) }
                }
                .frame(height: 56)

                SectionLabel(text: "Colors")
                Grid(horizontalSpacing: 6, verticalSpacing: 10) {
                    GridRow { ForEach(largePresets.prefix(4), id: \.self) { ColorDot(preset: $0, size: 34) } }
                    GridRow { ForEach(largePresets.suffix(4), id: \.self) { ColorDot(preset: $0, size: 34) } }
                }
                Spacer(minLength: 0)
            }

        default:
            VStack(spacing: 10) {
                Header()
                HStack(spacing: 8) { PowerButtons() }
            }
        }
    }
}

struct LampWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LampWidget", provider: LampProvider()) { _ in
            LampWidgetView()
        }
        .configurationDisplayName("Lamp")
        .description("Switch your lamp on or off, pick a color and set the brightness.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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
