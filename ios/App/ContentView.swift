import SwiftUI

@MainActor
final class LampViewModel: ObservableObject {
    @Published var bulbs: [DiscoveredBulb] = []
    @Published var savedName: String? = BulbController.shared.savedBulbName
    @Published var status: String?
    @Published var isBusy = false

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
        send(.on)
    }

    func send(_ command: LampCommand) {
        isBusy = true
        status = "Connecting…"
        Task { @MainActor in
            do {
                try await BulbController.shared.send(command)
                status = command == .on ? "Turned on ✓" : "Turned off ✓"
            } catch {
                status = error.localizedDescription
            }
            isBusy = false
        }
    }
}

struct ContentView: View {
    @StateObject private var model = LampViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                Section("Your bulb") {
                    if let name = model.savedName {
                        LabeledContent("Saved", value: name)
                    } else {
                        Text("No bulb chosen yet. Tap yours in the list below.")
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        Button {
                            model.send(.on)
                        } label: {
                            Label("On", systemImage: "lightbulb.max.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)

                        Button {
                            model.send(.off)
                        } label: {
                            Label("Off", systemImage: "lightbulb.slash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .controlSize(.large)
                    .disabled(model.savedName == nil || model.isBusy)

                    if let status = model.status {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    if model.bulbs.isEmpty {
                        Text("Searching…")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.bulbs) { bulb in
                        Button {
                            model.choose(bulb)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(bulb.name)
                                        .foregroundStyle(.primary)
                                    Text("Signal \(bulb.rssi) dBm")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if bulb.name == model.savedName {
                                    Image(systemName: "checkmark")
                                } else if bulb.looksLikeTriones {
                                    Image(systemName: "lightbulb")
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Nearby Bluetooth devices")
                        Spacer()
                        ProgressView()
                    }
                } footer: {
                    Text("Your bulb is usually called “Triones-…”. Fully close Happy Lighting first, because the bulb only accepts one connection at a time.")
                }

                Section("Add the widget") {
                    Text("Long-press your Home Screen › Edit › Add Widget › Lamp.")
                    Text("You can also add “Lamp On” / “Lamp Off” to Control Center, the Lock Screen or the Action button, or just say “Hey Siri, turn on Lamp”.")
                }
                .font(.callout)
            }
            .navigationTitle("Lamp")
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                model.startScan()
            } else {
                model.stopScan()
            }
        }
    }
}
