import AppIntents

// These intents are compiled into both the app and the widget extension.
// Conforming to LiveActivityIntent makes iOS run them in the *app's* process
// (launched silently in the background) instead of the short-lived widget
// process. That's where the Bluetooth connection, saved bulb and lamp state live.

struct TurnLampOnIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Turn Lamp On"
    static var description = IntentDescription("Turns the Triones bulb on.")

    func perform() async throws -> some IntentResult {
        try await BulbController.shared.send(.on)
        LampState.current.isOn = true
        return .result()
    }
}

struct TurnLampOffIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Turn Lamp Off"
    static var description = IntentDescription("Turns the Triones bulb off.")

    func perform() async throws -> some IntentResult {
        try await BulbController.shared.send(.off)
        LampState.current.isOn = false
        return .result()
    }
}

struct SetLampColorIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Set Lamp Color"
    static var description = IntentDescription("Turns the lamp on in the chosen color.")

    @Parameter(title: "Color", default: .warm)
    var preset: LampPreset

    init() {}

    init(preset: LampPreset) {
        self.preset = preset
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Set lamp to \(\.$preset)")
    }

    func perform() async throws -> some IntentResult {
        var state = LampState.current
        state.isOn = true
        state.color = preset.color
        for command in state.commands {
            try await BulbController.shared.send(command)
        }
        LampState.current = state
        return .result()
    }
}

struct SetLampBrightnessIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Set Lamp Brightness"
    static var description = IntentDescription("Turns the lamp on at the chosen brightness.")

    @Parameter(title: "Brightness", default: 100, inclusiveRange: (1, 100))
    var percent: Int

    init() {}

    init(percent: Int) {
        self.percent = percent
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Set lamp brightness to \(\.$percent)%")
    }

    func perform() async throws -> some IntentResult {
        var state = LampState.current
        state.isOn = true
        state.brightness = Double(min(100, max(1, percent))) / 100
        for command in state.commands {
            try await BulbController.shared.send(command)
        }
        LampState.current = state
        return .result()
    }
}
