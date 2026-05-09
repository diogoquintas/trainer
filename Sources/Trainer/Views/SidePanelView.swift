import SwiftUI

struct SidePanelView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject var engine: WorkoutEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CockpitStatusBlock(engine: engine, profile: viewModel.athleteProfile)

            HStack(spacing: 10) {
                WorkoutOptionsMenu(engine: engine)
                    .environmentObject(viewModel)

                ExportMenu(engine: engine)
                    .environmentObject(viewModel)
            }

            Divider()
                .overlay(.white.opacity(0.14))

            VStack(alignment: .leading, spacing: 12) {
                Text("STEP")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
                Text(engine.currentStep?.name ?? "Ready")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                ProgressView(value: progress)
                    .tint(.cyan)
                    .scaleEffect(y: 1.8)
                HStack {
                    TimeBadge(title: "Elapsed", value: WorkoutFormatters.duration(engine.elapsed), color: .white)
                    TimeBadge(title: "Left", value: WorkoutFormatters.duration(engine.timeRemainingInStep), color: .cyan)
                }
            }

            Divider()
                .overlay(.white.opacity(0.14))

            ControlButtons(engine: engine)

            Spacer()
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.065, green: 0.075, blue: 0.085),
                    Color(red: 0.025, green: 0.028, blue: 0.034)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var progress: Double {
        guard let index = engine.currentStepIndex, let step = engine.currentStep else { return 0 }
        let start = engine.workout.steps.prefix(index).reduce(0) { $0 + $1.duration }
        return min(1, max(0, (engine.elapsed - start) / step.duration))
    }
}

private struct WorkoutOptionsMenu: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject var engine: WorkoutEngine

    var body: some View {
        Menu {
            Picker(
                "Trainer Mode",
                selection: Binding(
                    get: { viewModel.trainerControlMode },
                    set: { viewModel.setTrainerControlMode($0) }
                )
            ) {
                ForEach(TrainerControlMode.allCases) { mode in
                    Label(mode.displayName, systemImage: icon(for: mode))
                        .tag(mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(viewModel.trainerControlMode.displayName, systemImage: icon(for: viewModel.trainerControlMode))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
        }
        .menuStyle(.button)
        .buttonStyle(CockpitMenuButtonStyle())
        .help("Workout options")
    }

    private func icon(for mode: TrainerControlMode) -> String {
        switch mode {
        case .erg:
            "bolt.fill"
        case .resistance:
            "dial.low.fill"
        case .off:
            "slash.circle"
        }
    }
}

private struct ExportMenu: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject var engine: WorkoutEngine

    var body: some View {
        Menu {
            Button {
                viewModel.exportCSV()
            } label: {
                Label("Export CSV", systemImage: "tablecells")
            }
            .disabled(engine.samples.isEmpty)

            Button {
                viewModel.exportJSON()
            } label: {
                Label("Export JSON", systemImage: "curlybraces")
            }
            .disabled(engine.samples.isEmpty)

            Divider()

            Button {
                Task {
                    await viewModel.connectStrava()
                }
            } label: {
                Label(
                    viewModel.isStravaConnected ? "Strava Connected" : (viewModel.isConnectingStrava ? "Connecting Strava" : "Connect Strava"),
                    systemImage: viewModel.isStravaConnected ? "checkmark.circle.fill" : "person.crop.circle.badge.plus"
                )
            }
            .disabled(viewModel.isStravaConnected || viewModel.isConnectingStrava)

            Button {
                Task {
                    await viewModel.uploadWorkoutToStrava()
                }
            } label: {
                Label(viewModel.isUploadingToStrava ? "Uploading to Strava" : "Upload to Strava", systemImage: "arrow.up.circle.fill")
            }
            .disabled(engine.samples.isEmpty || !viewModel.isStravaConnected || viewModel.isUploadingToStrava)

            Divider()

            Button {
                viewModel.copyTrainerCommunicationLog()
            } label: {
                Label("Copy Trainer Log (\(viewModel.trainerCommunicationLog.count))", systemImage: "doc.on.doc")
            }
            .disabled(viewModel.trainerCommunicationLog.isEmpty)

            Button {
                viewModel.clearTrainerCommunicationLog()
            } label: {
                Label("Clear Trainer Log", systemImage: "trash")
            }
            .disabled(viewModel.trainerCommunicationLog.isEmpty)
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
        }
        .menuStyle(.button)
        .buttonStyle(CockpitMenuButtonStyle())
        .help("Export options")
    }
}

private struct CockpitStatusBlock: View {
    @ObservedObject var engine: WorkoutEngine
    let profile: AthleteProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("WORKOUT")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(engine.workout.steps.count)")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("steps")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.56))
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(WorkoutFormatters.duration(engine.workout.totalDuration))
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
                Text("total")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.56))
            }

            HStack(spacing: 8) {
                ProfileBadge(title: "FTP", value: "\(profile.ftp)", unit: "W", color: .orange)
                ProfileBadge(title: "HRT", value: "\(profile.thresholdHeartRateBPM)", unit: "bpm", color: .red)
            }
        }
    }
}

private struct ProfileBadge: View {
    let title: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.46))
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                Text(unit)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TimeBadge: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.46))
            Text(value)
                .font(.system(size: 21, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ControlButtons: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject var engine: WorkoutEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CONTROL")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))

            VirtualGearControl(engine: engine)

            Button {
                engine.start()
            } label: {
                Label("START", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .font(.system(size: 18, weight: .black, design: .rounded))
            }
            .buttonStyle(CockpitButtonStyle(color: .green))
            .disabled(engine.state == .running || engine.state == .paused)

            Button {
                engine.state == .paused ? engine.resume() : engine.pause()
            } label: {
                Label(engine.state == .paused ? "RESUME" : "PAUSE", systemImage: engine.state == .paused ? "playpause.fill" : "pause.fill")
                    .frame(maxWidth: .infinity)
                    .font(.system(size: 16, weight: .black, design: .rounded))
            }
            .buttonStyle(CockpitButtonStyle(color: .cyan))
            .disabled(engine.state != .running && engine.state != .paused)

            Button(role: .destructive) {
                engine.stop()
            } label: {
                Label("STOP", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
                    .font(.system(size: 16, weight: .black, design: .rounded))
            }
            .buttonStyle(CockpitButtonStyle(color: .red))
            .disabled(engine.state == .stopped)
        }
    }
}

private struct VirtualGearControl: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject var engine: WorkoutEngine

    var body: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.shiftVirtualGear(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(GearButtonStyle())
            .disabled(!canShiftDown)
            .help("Shift down")

            Text("\(engine.currentVirtualGear)")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )

            Button {
                viewModel.shiftVirtualGear(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(GearButtonStyle())
            .disabled(!canShiftUp)
            .help("Shift up")
        }
        .frame(height: 34)
        .opacity(viewModel.trainerControlMode == .off ? 0.72 : 1)
    }

    private var canShiftDown: Bool {
        viewModel.trainerControlMode == .resistance && viewModel.manualVirtualGear > WorkoutEngine.virtualGearRange.lowerBound
    }

    private var canShiftUp: Bool {
        viewModel.trainerControlMode == .resistance && viewModel.manualVirtualGear < WorkoutEngine.virtualGearRange.upperBound
    }
}

private struct GearButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? .white : .white.opacity(0.28))
            .background(.white.opacity(backgroundOpacity(isPressed: configuration.isPressed)), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(isEnabled ? 0.12 : 0.06), lineWidth: 1)
            )
    }

    private func backgroundOpacity(isPressed: Bool) -> Double {
        guard isEnabled else { return 0.035 }
        return isPressed ? 0.18 : 0.09
    }
}

private struct CockpitMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .foregroundStyle(.white)
            .background(.white.opacity(configuration.isPressed ? 0.16 : 0.09), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
    }
}

private struct CockpitButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 13)
            .foregroundStyle(.black)
            .background(color.opacity(configuration.isPressed ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
