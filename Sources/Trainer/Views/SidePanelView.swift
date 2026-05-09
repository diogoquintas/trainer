import SwiftUI

struct SidePanelView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject var engine: WorkoutEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CockpitStatusBlock(engine: engine)

            Divider()
                .overlay(TrainerTheme.Surface.separator)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("STEP")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(TrainerTheme.Surface.textTertiary)
                    Spacer()
                    Text(stepCounter)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(TrainerTheme.Surface.textSecondary)
                }
                Text(engine.currentStep?.name ?? "Ready")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(TrainerTheme.Surface.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                ProgressView(value: progress)
                    .tint(TrainerTheme.Status.time)
                    .scaleEffect(y: 1.8)
                HStack {
                    TimeBadge(title: "Elapsed", value: WorkoutFormatters.duration(stepElapsed), color: TrainerTheme.Surface.textPrimary)
                    TimeBadge(title: "Left", value: WorkoutFormatters.duration(engine.timeRemainingInStep), color: TrainerTheme.Status.time)
                }
            }

            Divider()
                .overlay(TrainerTheme.Surface.separator)

            ControlButtons(engine: engine)

            Spacer()
        }
        .padding(18)
        .background(TrainerTheme.Surface.panelElevated, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(TrainerTheme.Surface.separator, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.34), radius: 18, x: 0, y: 8)
    }

    private var progress: Double {
        guard let index = engine.currentStepIndex, let step = engine.currentStep else { return 0 }
        let start = engine.workout.steps.prefix(index).reduce(0) { $0 + $1.duration }
        return min(1, max(0, (engine.elapsed - start) / step.duration))
    }

    private var stepElapsed: TimeInterval {
        guard let index = engine.currentStepIndex else { return 0 }
        let start = engine.workout.steps.prefix(index).reduce(0) { $0 + $1.duration }
        return max(0, engine.elapsed - start)
    }

    private var stepCounter: String {
        guard let index = engine.currentStepIndex else { return "0/\(engine.workout.steps.count)" }
        return "\(index + 1)/\(engine.workout.steps.count)"
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

            Button {
                viewModel.exportWorkoutProgressImage()
            } label: {
                Label("Export Progress Image", systemImage: "photo")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WORKOUT")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(TrainerTheme.Surface.textTertiary)

            VStack(alignment: .leading, spacing: 4) {
                Text(engine.workout.name)
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .foregroundStyle(TrainerTheme.Surface.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                if let description = engine.workout.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(TrainerTheme.Surface.textSecondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ProgressView(value: workoutProgress)
                .tint(TrainerTheme.Status.time)
                .scaleEffect(y: 1.8)

            HStack {
                TimeBadge(title: "Elapsed", value: WorkoutFormatters.duration(engine.elapsed), color: TrainerTheme.Surface.textPrimary)
                TimeBadge(title: "Left", value: WorkoutFormatters.duration(totalRemaining), color: TrainerTheme.Status.time)
            }
        }
    }

    private var totalRemaining: TimeInterval {
        max(0, engine.workout.totalDuration - engine.elapsed)
    }

    private var workoutProgress: Double {
        guard engine.workout.totalDuration > 0 else { return 0 }
        return min(1, max(0, engine.elapsed / engine.workout.totalDuration))
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
                .foregroundStyle(TrainerTheme.Surface.textTertiary)
            Text(value)
                .font(.system(size: 21, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(TrainerTheme.Surface.subtleFill, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ControlButtons: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject var engine: WorkoutEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CONTROL")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(TrainerTheme.Surface.textTertiary)

            VirtualGearControl(engine: engine)

            HStack(spacing: 8) {
                Button {
                    if engine.state == .paused {
                        engine.resume()
                    } else {
                        engine.start()
                    }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(CockpitButtonStyle(color: TrainerTheme.Control.start))
                .disabled(engine.state == .running)
                .help("Start")
                .accessibilityLabel("Start")

                Button {
                    engine.pause()
                } label: {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(CockpitButtonStyle(color: TrainerTheme.Surface.neutralControl))
                .disabled(engine.state != .running)
                .help("Pause")
                .accessibilityLabel("Pause")

                Button(role: .destructive) {
                    engine.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(CockpitButtonStyle(color: TrainerTheme.Control.stop))
                .disabled(engine.state == .stopped)
                .help("Stop")
                .accessibilityLabel("Stop")
            }

            HStack(spacing: 10) {
                WorkoutOptionsMenu(engine: engine)
                    .environmentObject(viewModel)

                ExportMenu(engine: engine)
                    .environmentObject(viewModel)
            }
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
                .foregroundStyle(TrainerTheme.Surface.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(TrainerTheme.Surface.subtleFill, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(TrainerTheme.Surface.separator, lineWidth: 1)
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
            .foregroundStyle(isEnabled ? TrainerTheme.Surface.textPrimary : TrainerTheme.Surface.textTertiary)
            .background(fill(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(TrainerTheme.Surface.separator.opacity(isEnabled ? 1 : 0.55), lineWidth: 1)
            )
    }

    private func fill(isPressed: Bool) -> Color {
        guard isEnabled else { return TrainerTheme.Surface.subtleFill.opacity(0.6) }
        return isPressed ? TrainerTheme.Surface.strongerFill : TrainerTheme.Surface.subtleFill
    }
}

private struct CockpitMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .foregroundStyle(TrainerTheme.Surface.textPrimary)
            .background(configuration.isPressed ? TrainerTheme.Surface.strongerFill : TrainerTheme.Surface.subtleFill, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(TrainerTheme.Surface.separator, lineWidth: 1)
            )
    }
}

private struct CockpitButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? TrainerTheme.Surface.textPrimary : TrainerTheme.Surface.textTertiary)
            .background(fill(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(strokeColor, lineWidth: 1)
            )
            .shadow(color: isEnabled ? color.opacity(0.24) : .clear, radius: 12, x: 0, y: 5)
            .opacity(configuration.isPressed && isEnabled ? 0.85 : 1)
    }

    private func fill(isPressed: Bool) -> Color {
        guard isEnabled else { return TrainerTheme.Surface.subtleFill.opacity(0.48) }
        return color.opacity(isPressed ? 0.58 : 0.78)
    }

    private var strokeColor: Color {
        isEnabled ? color.opacity(0.90) : TrainerTheme.Surface.separator.opacity(0.55)
    }
}
