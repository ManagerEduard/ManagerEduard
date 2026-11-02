import AppIntents
import Foundation
import SwiftUI

/// A colour the lamp can show. RGB is normalised so the brightest channel is 1;
/// brightness is applied separately when building the Bluetooth command.
struct LampColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    /// Uses the bulb's dedicated warm-white LEDs instead of mixing RGB.
    var isWarmWhite: Bool = false

    static let warmWhite = LampColor(red: 1.0, green: 0.76, blue: 0.46, isWarmWhite: true)

    /// Creates a colour from arbitrary RGB values (0…1), normalising its intensity.
    init(red: Double, green: Double, blue: Double, isWarmWhite: Bool = false) {
        let peak = max(red, green, blue, 0.001)
        self.red = min(1, max(0, red / peak))
        self.green = min(1, max(0, green / peak))
        self.blue = min(1, max(0, blue / peak))
        self.isWarmWhite = isWarmWhite
    }

    func command(brightness: Double) -> LampCommand {
        let level = min(1, max(0.02, brightness))
        if isWarmWhite {
            return .warmWhite(level: Self.byte(level))
        }
        return .color(red: Self.byte(red * level), green: Self.byte(green * level), blue: Self.byte(blue * level))
    }

    private static func byte(_ value: Double) -> UInt8 {
        UInt8((min(1, max(0, value)) * 255).rounded())
    }
}

/// Last known state of the lamp, remembered between launches.
/// The bulb can't be queried reliably, so this reflects what we last sent.
struct LampState: Codable, Equatable {
    var isOn: Bool = false
    var brightness: Double = 1.0
    var color: LampColor = .warmWhite

    private static let key = "lampState"

    static var current: LampState {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let state = try? JSONDecoder().decode(LampState.self, from: data)
            else { return LampState() }
            return state
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }

    /// Commands that bring the bulb to this state.
    var commands: [LampCommand] {
        isOn ? [.on, color.command(brightness: brightness)] : [.off]
    }
}

/// Named colours used by the app, the widget and Siri.
enum LampPreset: String, AppEnum, CaseIterable {
    case warm
    case red
    case orange
    case yellow
    case green
    case cyan
    case blue
    case purple
    case pink

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Lamp Color"

    static var caseDisplayRepresentations: [LampPreset: DisplayRepresentation] = [
        .warm: "Warm White",
        .red: "Red",
        .orange: "Orange",
        .yellow: "Yellow",
        .green: "Green",
        .cyan: "Cyan",
        .blue: "Blue",
        .purple: "Purple",
        .pink: "Pink",
    ]

    var name: String {
        switch self {
        case .warm: return "Warm"
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .cyan: return "Cyan"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .pink: return "Pink"
        }
    }

    var color: LampColor {
        switch self {
        case .warm: return .warmWhite
        case .red: return LampColor(red: 1, green: 0.08, blue: 0.05)
        case .orange: return LampColor(red: 1, green: 0.42, blue: 0)
        case .yellow: return LampColor(red: 1, green: 0.85, blue: 0)
        case .green: return LampColor(red: 0.1, green: 1, blue: 0.25)
        case .cyan: return LampColor(red: 0, green: 0.85, blue: 1)
        case .blue: return LampColor(red: 0.1, green: 0.25, blue: 1)
        case .purple: return LampColor(red: 0.6, green: 0.15, blue: 1)
        case .pink: return LampColor(red: 1, green: 0.2, blue: 0.6)
        }
    }
}

extension LampColor {
    var swiftUIColor: Color { Color(red: red, green: green, blue: blue) }
}

extension LampColor {
    /// Whether dark text/icons read better on top of this colour.
    var isLight: Bool {
        0.299 * red + 0.587 * green + 0.114 * blue > 0.62
    }
}
