import SwiftUI
import UIKit

// MARK: - View model

@MainActor
final class LampViewModel: ObservableObject {
    @Published private(set) var state = LampState.current
    @Published var bulbs: [DiscoveredBulb] = []
    @Published var savedName: String? = BulbController.shared.savedBulbName
    @Published var message: String?

    /// Whether the state changed since the last command was sent.
    private var dirty = false
    private var sending = false
    /// Power state we last successfully sent. nil = unknown, so resend it.
    private var sentPower: Bool?

    var hasBulb: Bool { savedName != nil }

    func reload() {
        state = LampState.current
        savedName = BulbController.shared.savedBulbName
        sentPower = nil // the widget or Happy Lighting may have changed it
    }

    // MARK: Controls

    func togglePower() {
        state.isOn.toggle()
        sentPower = nil
        commit()
    }

    func setBrightness(_ value: Double) {
        state.brightness = min(1, max(0.02, value))
        state.isOn = true
        commit()
    }

    func setColor(_ color: LampColor) {
        state.color = color
        state.isOn = true
        commit()
    }

    /// Saves the state and sends it to the bulb. While a command is in flight,
    /// further changes (e.g. slider drags) are coalesced into one follow-up send.
    private func commit() {
        LampState.current = state
        dirty = true
        pump()
    }

    private func pump() {
        guard hasBulb, !sending, dirty else { return }
        dirty = false
        sending = true

        let target = state
        var commands: [LampCommand] = []
        if target.isOn {
            if sentPower != true { commands.append(.on) }
            commands.append(target.color.command(brightness: target.brightness))
        } else {
            commands.append(.off)
        }

        Task { @MainActor in
            do {
                for command in commands {
                    try await BulbController.shared.send(command)
                }
                sentPower = target.isOn
                withAnimation { message = nil }
            } catch {
                sentPower = nil
                withAnimation { message = error.localizedDescription }
            }
            sending = false
            pump()
        }
    }

    // MARK: Setup

    func startScan() {
        BulbController.shared.startScanning { [weak self] bulb in
            Task { @MainActor in self?.add(bulb) }
        }
    }

    func stopScan() {
        BulbController.shared.stopScanning()
    }

    private func add(_ bulb: DiscoveredBulb) {
        if let index = bulbs.firstIndex(where: { $0.id == bulb.id }) {
            bulbs[index].rssi = bulb.rssi
        } else {
            bulbs.append(bulb)
        }
        bulbs.sort { lhs, rhs in
            if lhs.looksLikeTriones != rhs.looksLikeTriones { return lhs.looksLikeTriones }
            return lhs.rssi > rhs.rssi
        }
    }

    func choose(_ bulb: DiscoveredBulb) {
        BulbController.shared.saveBulb(bulb)
        savedName = bulb.name
        state.isOn = true
        sentPower = nil
        commit()
    }
}

// MARK: - Main screen

struct ContentView: View {
    @StateObject private var model = LampViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSetup = false

    private var tint: Color {
        model.state.isOn ? model.state.color.swiftUIColor : Color(.systemGray3)
    }

    private var percent: Int { Int((model.state.brightness * 100).rounded()) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    statusHeader

                    HStack(alignment: .center, spacing: 36) {
                        BrightnessSlider(
                            value: Binding(
                                get: { model.state.brightness },
                                set: { model.setBrightness($0) }
                            ),
                            tint: tint,
                            isOn: model.state.isOn
                        )
                        .frame(width: 116, height: 330)

                        VStack(spacing: 10) {
                            PowerButton(isOn: model.state.isOn, color: model.state.color) {
                                model.togglePower()
                            }
                            Text(model.state.isOn ? "On" : "Off")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)

                    ColorsCard(model: model)

                    if let message = model.message {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.primary)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(background)
            .navigationTitle("Lamp")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSetup = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingSetup) {
                SetupView(model: model)
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            model.reload()
            if !model.hasBulb { showingSetup = true }
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: model.state.isOn ? "lightbulb.max.fill" : "lightbulb")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(model.state.isOn ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 56, height: 56)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(model.state.isOn ? "\(percent)% brightness" : "Off")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .contentTransition(.numericText())
                Text(model.savedName ?? "No bulb selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .animation(.snappy, value: model.state)
    }

    private var background: some View {
        ZStack {
            Color(.systemGroupedBackground)
            LinearGradient(
                colors: [tint.opacity(model.state.isOn ? 0.45 : 0.12), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.5), value: model.state)
    }
}

// MARK: - Brightness slider (Home app style)

struct BrightnessSlider: View {
    @Binding var value: Double
    var tint: Color
    var isOn: Bool

    @State private var dragStart: Double?

    private var level: Double { isOn ? value : 0 }

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(.ultraThinMaterial)

                Rectangle()
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                    .frame(height: height * level)

                Image(systemName: level > 0.5 ? "sun.max.fill" : "sun.min.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(level > 0.12 ? Color.white : Color.secondary)
                    .shadow(color: .black.opacity(0.25), radius: 3)
                    .padding(.bottom, 24)
            }
            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: tint.opacity(isOn ? 0.5 : 0), radius: 28, y: 10)
            .contentShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let start = dragStart ?? level
                        if dragStart == nil { dragStart = start }
                        value = min(1, max(0.02, start - gesture.translation.height / height))
                    }
                    .onEnded { _ in dragStart = nil }
            )
        }
        .animation(.interactiveSpring(response: 0.25), value: level)
        .sensoryFeedback(.selection, trigger: Int(level * 20))
        .accessibilityElement()
        .accessibilityLabel("Brightness")
        .accessibilityValue(isOn ? "\(Int(value * 100)) percent" : "Off")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, value + 0.1)
            case .decrement: value = max(0.02, value - 0.1)
            @unknown default: break
            }
        }
    }
}

// MARK: - Power button

struct PowerButton: View {
    let isOn: Bool
    let color: LampColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "power")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(isOn ? (color.isLight ? Color.black.opacity(0.75) : Color.white) : Color.primary)
                .frame(width: 84, height: 84)
                .background {
                    Circle().fill(isOn ? AnyShapeStyle(color.swiftUIColor.gradient) : AnyShapeStyle(.ultraThinMaterial))
                }
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: color.swiftUIColor.opacity(isOn ? 0.55 : 0), radius: 18)
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(.impact(weight: .medium), trigger: isOn)
        .accessibilityLabel(isOn ? "Turn off" : "Turn on")
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Colours

struct ColorsCard: View {
    @ObservedObject var model: LampViewModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    private var customBinding: Binding<Color> {
        Binding(
            get: { model.state.color.swiftUIColor },
            set: { newColor in
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                UIColor(newColor).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                model.setColor(LampColor(red: Double(red), green: Double(green), blue: Double(blue)))
            }
        )
    }

    private var isCustom: Bool {
        !LampPreset.allCases.contains { $0.color == model.state.color }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Colors")
                .font(.system(.headline, design: .rounded))

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(LampPreset.allCases, id: \.self) { preset in
                    Button {
                        model.setColor(preset.color)
                    } label: {
                        Swatch(
                            fill: AnyShapeStyle(preset.color.swiftUIColor.gradient),
                            name: preset.name,
                            isSelected: model.state.isOn && model.state.color == preset.color
                        )
                    }
                    .buttonStyle(PressableStyle())
                    .sensoryFeedback(.selection, trigger: model.state.color == preset.color)
                }

                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                            .frame(width: 46, height: 46)
                        ColorPicker("Custom color", selection: customBinding, supportsOpacity: false)
                            .labelsHidden()
                            .scaleEffect(1.7)
                            .opacity(0.02) // invisible, but still receives the tap
                    }
                    .padding(4)
                    .overlay(Circle().strokeBorder(isCustom && model.state.isOn ? Color.primary : .clear, lineWidth: 2.5))
                    Text("Custom")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

struct Swatch: View {
    let fill: AnyShapeStyle
    let name: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Circle()
                .fill(fill)
                .frame(width: 46, height: 46)
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                .padding(4)
                .overlay(Circle().strokeBorder(isSelected ? Color.primary : .clear, lineWidth: 2.5))
            Text(name)
                .font(.caption2)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Setup sheet

struct SetupView: View {
    @ObservedObject var model: LampViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "lightbulb.max.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.orange.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading) {
                            Text(model.savedName ?? "No bulb selected")
                                .font(.headline)
                            Text(model.hasBulb ? "Connected via Bluetooth" : "Choose your bulb below")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    if model.bulbs.isEmpty {
                        HStack {
                            ProgressView()
                            Text("Searching for bulbs…")
                                .foregroundStyle(.secondary)
                                .padding(.leading, 8)
                        }
                    }
                    ForEach(model.bulbs) { bulb in
                        Button {
                            model.choose(bulb)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: bulb.looksLikeTriones ? "lightbulb.fill" : "dot.radiowaves.left.and.right")
                                    .foregroundStyle(bulb.looksLikeTriones ? .orange : .secondary)
                                    .frame(width: 24)
                                VStack(alignment: .leading) {
                                    Text(bulb.name)
                                        .foregroundStyle(.primary)
                                    Text(signalText(bulb.rssi))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if bulb.name == model.savedName {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Nearby devices")
                } footer: {
                    Text("Your bulb is usually called “Triones-…”. Fully close Happy Lighting first, because the bulb accepts only one connection at a time.")
                }

                Section("Widgets & Siri") {
                    Label("Long-press the Home Screen › Edit › Add Widget › Lamp", systemImage: "square.grid.2x2.fill")
                    Label("Add “Lamp On” and “Lamp Off” to Control Center", systemImage: "switch.2")
                    Label("“Hey Siri, set Lamp to blue”", systemImage: "waveform")
                }
                .font(.callout)
            }
            .navigationTitle("Bulb Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { model.startScan() }
        .onDisappear { model.stopScan() }
    }

    private func signalText(_ rssi: Int) -> String {
        switch rssi {
        case -60...0: return "Excellent signal"
        case -75 ..< -60: return "Good signal"
        default: return "Weak signal"
        }
    }
}
