# Lamp — iPhone widget for a Triones Bluetooth bulb

A tiny iOS app that controls a **Triones** ("Happy Lighting") Bluetooth bulb, with:

- a Home app–style control screen: brightness slider, power button, color swatches and a custom color picker
- Home Screen widgets in three sizes (On/Off, colors, brightness presets)
- "Lamp On" / "Lamp Off" controls for Control Center, the Lock Screen and the Action button
- Siri & Shortcuts actions ("Hey Siri, turn on Lamp", "Set Lamp to blue")

Requires iOS 18+. The phone has to be within Bluetooth range of the bulb.

## How it gets built

You don't need Xcode. Every push to `ios/` triggers the **Build iOS app** GitHub Action,
which builds an unsigned `LampControl.ipa` and attaches it to a new
[Release](../../releases). You sign and install it yourself with your free Apple ID via SideStore.

## Installing (free Apple ID, no $99 account)

### One-time: install SideStore (needs a computer once)
1. Follow the official guide at <https://docs.sidestore.io> → *Installation*.
   On your Mac this means running their installer with your iPhone plugged in over USB.
   It installs SideStore on the phone and creates the "pairing file" it needs.
2. On the iPhone: Settings › General › VPN & Device Management → trust your Apple ID,
   and turn on **Developer Mode** (Settings › Privacy & Security) when asked.
3. Set up SideStore's on-device refresh as described in their docs (it uses a
   local VPN/"LocalDevVPN" app). From now on, no computer is needed.

### Install the Lamp app (all on the phone)
1. On the iPhone, open the latest [Release](../../releases) and download **LampControl.ipa**.
2. Share it to **SideStore** (or in SideStore: *My Apps › +* and pick the file).
3. Open **Lamp**, allow Bluetooth, fully close Happy Lighting, and tap your bulb
   (usually "Triones-…") in the list. The bulb should turn on.
4. Add the widget: long-press the Home Screen › Edit › Add Widget › **Lamp**.

### Keeping it alive
Free Apple ID signatures last **7 days**. Open SideStore and tap *Refresh All*
before then (or let its background refresh do it). If it expires, just refresh;
nothing is lost.

## How it works

Triones bulbs expose BLE service `FFD5` with write characteristic `FFD9`:

| Command          | Bytes                  |
|------------------|------------------------|
| On               | `CC 23 33`             |
| Off              | `CC 24 33`             |
| RGB color        | `56 RR GG BB 00 F0 AA` |
| Warm white level | `56 00 00 00 WW 0F AA` |

The bulb has no separate brightness command, so brightness is applied by scaling the
RGB (or warm-white) values. The last state sent is remembered in `LampState`.

The widget buttons run App Intents that conform to `LiveActivityIntent`, so iOS executes
them in the app's own process (launched in the background, with the `bluetooth-central`
background mode). The app connects to the saved bulb, writes the command and disconnects
a few seconds later so Happy Lighting can still connect.

Code layout:

- `ios/Shared/BulbController.swift`: Bluetooth logic
- `ios/Shared/LampState.swift`: colors, presets and the remembered lamp state
- `ios/Shared/LampIntents.swift`: On/Off/color/brightness intents used by the widget, controls and Siri
- `ios/App/`: setup screen (pick your bulb, test buttons)
- `ios/Widget/`: widget + Control Center controls
- `ios/project.yml`: XcodeGen project spec
- `scripts/make_icon.py`: draws the app icon
