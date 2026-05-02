import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Binding var isImporting: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Trainer")
                    .font(.title2.bold())
                Text(viewModel.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

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

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Workouts")
                        .font(.headline)
                    Spacer()
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
                            .onTapGesture {
                                viewModel.selectWorkout(workout)
                            }
                    }
                }
                .frame(minHeight: 190)

                Button {
                    isImporting = true
                } label: {
                    Label("Import .zwo", systemImage: "square.and.arrow.down")
                }
            }

            Spacer()
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
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
