import AppIntents
import SwiftUI

@main
struct LampControlApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Exposes the intents to Siri and the Shortcuts app.
struct LampShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TurnLampOnIntent(),
            phrases: ["Turn on \(.applicationName)", "\(.applicationName) on"],
            shortTitle: "Lamp On",
            systemImageName: "lightbulb.max.fill"
        )
        AppShortcut(
            intent: TurnLampOffIntent(),
            phrases: ["Turn off \(.applicationName)", "\(.applicationName) off"],
            shortTitle: "Lamp Off",
            systemImageName: "lightbulb.slash"
        )
    }
}
