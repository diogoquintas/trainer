# Trainer

Personal macOS SwiftUI MVP for running structured smart-trainer workouts.

The app starts in simulation mode, and can also connect to Bluetooth LE fitness devices. It includes:

- SwiftUI macOS app entry point
- Modular data models and service protocols
- Simulated trainer and heart-rate services
- Bluetooth discovery for FTMS/Cycling Power smart trainers and Heart Rate Service broadcasts
- Live Bluetooth telemetry ingestion for power, cadence, speed, and heart rate where supported
- Best-effort FTMS ERG target writes for compatible smart trainers
- Basic workout engine with start, pause, resume, stop, and finish states
- `.zwo` parser for common Zwift workout elements
- ERG target handoff through a `TrainerServicing` protocol
- Three Apple Charts views for HR, cadence, and power actual-vs-target
- CSV and JSON export of recorded workout samples
- Industry-style cadence split: live values and chart buffer update at 10 Hz while activity samples are recorded/exported at 1 Hz
- Placeholder `StravaServicing` protocol for future OAuth/upload work

## Run

```bash
Scripts/run-app.sh
```

This builds the SwiftPM executable, wraps it in a local unsigned `.app` bundle under `Build/`, and opens it with macOS LaunchServices. The app is local-only and does not require the App Store.

On first Bluetooth scan, macOS may ask for Bluetooth permission. The generated local app bundle includes the required usage descriptions.

## Build

```bash
swift build
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
