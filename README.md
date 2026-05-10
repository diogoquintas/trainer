# Trainer

Personal macOS SwiftUI MVP for running structured smart-trainer workouts.

The app starts in simulation mode, and can also connect to Bluetooth LE fitness devices. It includes:

- SwiftUI macOS app entry point
- Modular data models and service protocols
- Simulated trainer and heart-rate services
- Bluetooth discovery for FTMS/Cycling Power smart trainers and Heart Rate Service broadcasts
- Live Bluetooth telemetry ingestion for power, cadence, speed, and heart rate where supported
- Best-effort FTMS ERG target-power and resistance-level writes for compatible smart trainers
- Basic workout engine with start, pause, resume, stop, and finish states
- `.zwo` parser for common Zwift workout elements and `textevent` notifications
- Native workout notifications for ZWO text cues and one-minute step-change warnings
- ERG, resistance, and off trainer-control modes through a `TrainerServicing` protocol
- Three Apple Charts views for HR, cadence, and power actual-vs-target
- CSV, JSON, and TCX export of recorded workout samples
- Strava OAuth connection and indoor ride upload from the finished workout samples
- Industry-style cadence split: live values and chart buffer update at 10 Hz while activity samples are recorded/exported at 1 Hz

## Run

```bash
Scripts/run-app.sh
```

This builds the SwiftPM executable, wraps it in a local unsigned `.app` bundle under `Build/`, and opens it with macOS LaunchServices. The app is local-only and does not require the App Store.

On first Bluetooth scan, macOS may ask for Bluetooth permission. The generated local app bundle includes the required usage descriptions.

To show the notification debug panel while troubleshooting local macOS delivery, enable it before launch:

```bash
defaults write local.personal.Trainer trainer.notificationDebugEnabled -bool true
```

## Build

```bash
swift build
```

## Strava Uploads

Create a Strava API application at <https://www.strava.com/settings/api>, then store the app credentials in macOS defaults before running the app:

```bash
defaults write local.personal.Trainer strava.clientID "YOUR_CLIENT_ID"
defaults write local.personal.Trainer strava.clientSecret "YOUR_CLIENT_SECRET"
```

Set the Strava app's **Authorization Callback Domain** to `localhost`. In the app, finish or stop a workout after samples have been recorded, click **CONNECT** in the export panel, authorize `activity:write`, then click **STRAVA**. The app generates a TCX file, marks it as a trainer activity, refreshes the Strava access token when needed, and stores the latest refresh token in user defaults.

For local command-line runs you can also provide:

```bash
export STRAVA_CLIENT_ID="YOUR_CLIENT_ID"
export STRAVA_CLIENT_SECRET="YOUR_CLIENT_SECRET"
export STRAVA_REFRESH_TOKEN="OPTIONAL_EXISTING_REFRESH_TOKEN"
```

## Project Layout

- `Models`: workout, reading, sample, and device state types
- `Protocols`: Bluetooth, trainer, HR, parser, recorder, and Strava interfaces
- `Mocks`: simulation implementations for MVP development without hardware
- `Services`: CoreBluetooth device discovery, telemetry parsing, and FTMS control
- `Workout`: `.zwo` parser and workout execution engine
- `Data`: workout sample recorder and exporters
- `ViewModels`: app-level orchestration
- `Views`: SwiftUI screens, charts, side panel, and controls
- `Fixtures`: sample `.zwo` workout

Bluetooth is implemented behind `BluetoothManaging`, `TrainerServicing`, and `HeartRateServicing`, so the workout engine can run with simulated devices, real devices, or one of each.
