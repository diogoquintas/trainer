import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Binding var isImporting: Bool
    @Binding var isImportingRoute: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DeviceConnectionView(
                title: "Trainer",
                state: viewModel.trainerConnectionText,
                detail: viewModel.trainerSource == .simulation ? "Synthetic power, cadence, and ERG response" : "FTMS / Cycling Power telemetry",
                devices: viewModel.availableTrainers,
                scanAction: {
                    await viewModel.scanForBluetoothTrainers()
                },
                simulationAction: {
                    await viewModel.useSimulationTrainer()
                },
                connectAction: { device in
                    await viewModel.connectBluetoothTrainer(device)
                }
            )

            DeviceConnectionView(
                title: "Heart Rate",
                state: viewModel.heartRateConnectionText,
                detail: viewModel.heartRateSource == .simulation ? "Synthetic heart-rate curve" : "Standard Heart Rate Measurement",
                devices: viewModel.availableHeartRateDevices,
                scanAction: {
                    await viewModel.scanForBluetoothHeartRateDevices()
                },
                simulationAction: {
                    await viewModel.useSimulationHeartRate()
                },
                connectAction: { device in
                    await viewModel.connectBluetoothHeartRate(device)
                }
            )

            Divider()

            AthleteStatsView()

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Workouts")
                        .font(.headline)
                    Spacer()
                    Button {
                        viewModel.removeSelectedWorkout()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .help("Remove selected workout")
                    Button {
                        isImporting = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Import .zwo")
                }

                List(selection: $viewModel.selectedWorkoutID) {
                    ForEach(viewModel.workouts) { workout in
                        WorkoutLibraryRow(workout: workout)
                            .tag(workout.id)
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button(role: .destructive) {
                                    viewModel.removeWorkout(id: workout.id)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                }
                .frame(minHeight: 190)
                .onChange(of: viewModel.selectedWorkoutID) { _, workoutID in
                    viewModel.selectWorkout(id: workoutID)
                }
                .onDeleteCommand {
                    viewModel.removeSelectedWorkout()
                }

            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Virtual Routes")
                        .font(.headline)
                    Spacer()
                    Button {
                        viewModel.removeSelectedRoute()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(viewModel.selectedRoute == nil)
                    .help("Remove selected route")
                    Button {
                        isImportingRoute = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Import .gpx")
                }

                if viewModel.routes.isEmpty {
                    Text("No routes loaded")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    List(selection: $viewModel.selectedRouteID) {
                        ForEach(viewModel.routes) { route in
                            VirtualRouteLibraryRow(route: route)
                                .tag(route.id)
                                .contentShape(Rectangle())
                                .contextMenu {
                                    Button(role: .destructive) {
                                        viewModel.removeRoute(id: route.id)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .frame(minHeight: 95, maxHeight: 150)
                    .onChange(of: viewModel.selectedRouteID) { _, routeID in
                        viewModel.selectRoute(id: routeID)
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .background(TrainerTheme.Surface.sidebarBackground)
    }
}

private struct AthleteStatsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var draftProfile = AthleteProfile()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Athlete Stats")
                    .font(.headline)
                Spacer()
                Text(String(format: "%.1f W/kg", draftProfile.wattsPerKilogram))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    StatIntegerField(title: "FTP", suffix: "W", value: $draftProfile.ftp)
                    StatIntegerField(title: "HRT", suffix: "bpm", value: $draftProfile.thresholdHeartRateBPM)
                        .help("Heart-rate threshold")
                }
                GridRow {
                    StatIntegerField(title: "HRM", suffix: "bpm", value: $draftProfile.maxHeartRateBPM)
                        .help("Maximum heart rate")
                    StatIntegerField(title: "Rest", suffix: "bpm", value: $draftProfile.restingHeartRateBPM)
                }
                GridRow {
                    StatDoubleField(title: "Weight", suffix: "kg", value: $draftProfile.weightKg)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Difficulty")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { Double(draftProfile.trainerDifficultyPercent) },
                                    set: { draftProfile.trainerDifficultyPercent = Int($0.rounded()) }
                                ),
                                in: 0...100,
                                step: 5
                            )
                            Text("\(draftProfile.trainerDifficultyPercent)%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }
            }

            HStack {
                Button {
                    draftProfile = viewModel.athleteProfile
                } label: {
                    Label("Revert", systemImage: "arrow.uturn.backward")
                }
                .disabled(draftProfile == viewModel.athleteProfile)

                Spacer()

                Button {
                    viewModel.updateAthleteProfile(draftProfile)
                    draftProfile = viewModel.athleteProfile
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftProfile == viewModel.athleteProfile)
            }
            .controlSize(.small)
        }
        .onAppear {
            draftProfile = viewModel.athleteProfile
        }
        .onChange(of: viewModel.athleteProfile) { _, profile in
            guard draftProfile == profile else { return }
            draftProfile = profile
        }
    }
}

private struct StatIntegerField: View {
    let title: String
    let suffix: String
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                TextField(title, value: $value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                    .frame(width: 58)
                Text(suffix)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct StatDoubleField: View {
    let title: String
    let suffix: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                TextField(title, value: $value, format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                    .frame(width: 58)
                Text(suffix)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct WorkoutLibraryRow: View {
    let workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(workout.name)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
            Text("\(workout.steps.count) steps · \(WorkoutFormatters.duration(workout.totalDuration))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct VirtualRouteLibraryRow: View {
    let route: VirtualRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(route.name)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
            Text("\(WorkoutFormatters.distance(route.totalDistanceMeters)) · \(Int(route.elevationGainMeters.rounded())) m gain")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(route.hasCompleteElevation ? "Elevation: Open-Meteo / Copernicus DEM" : "Elevation: GPX data only")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

private struct DeviceConnectionView: View {
    let title: String
    let state: String
    let detail: String
    let devices: [DeviceDescriptor]
    let scanAction: () async -> Void
    let simulationAction: () async -> Void
    let connectAction: (DeviceDescriptor) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Image(systemName: state.contains("Connected") ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(state.contains("Connected") ? .green : .secondary)
            }
            Text(state)
                .font(.callout.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button {
                    Task { await scanAction() }
                } label: {
                    Label("Scan", systemImage: "dot.radiowaves.left.and.right")
                }

                Button {
                    Task { await simulationAction() }
                } label: {
                    Label("Simulation", systemImage: "waveform.path.ecg")
                }
            }
            .controlSize(.small)

            ForEach(devices.filter { $0.source == .bluetooth }) { device in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        if let rssi = device.rssi {
                            Text("\(rssi) dBm")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        Task { await connectAction(device) }
                    } label: {
                        Image(systemName: "link")
                    }
                    .buttonStyle(.borderless)
                    .help("Connect")
                }
                .padding(8)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
