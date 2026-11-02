import AppIntents

// These intents are compiled into both the app and the widget extension.
// Conforming to LiveActivityIntent makes iOS run them in the *app's* process
// (launched silently in the background) instead of the short-lived widget
// process. That's where the Bluetooth connection and saved bulb live.

struct TurnLampOnIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Turn Lamp On"
    static var description = IntentDescription("Turns the Triones bulb on.")

    func perform() async throws -> some IntentResult {
        try await BulbController.shared.send(.on)
        return .result()
    }
}

struct TurnLampOffIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Turn Lamp Off"
    static var description = IntentDescription("Turns the Triones bulb off.")

    func perform() async throws -> some IntentResult {
        try await BulbController.shared.send(.off)
        return .result()
    }
}
