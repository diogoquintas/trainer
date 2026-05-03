import SwiftUI

struct SidePanelView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject var engine: WorkoutEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CockpitStatusBlock(engine: engine)

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

            VStack(alignment: .leading, spacing: 10) {
                Text("EXPORT")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
                HStack {
                    Button {
                        viewModel.exportCSV()
                    } label: {
                        Label("CSV", systemImage: "tablecells")
                            .frame(maxWidth: .infinity)
                    }

                    Button {
                        viewModel.exportJSON()
                    } label: {
                        Label("JSON", systemImage: "curlybraces")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(engine.samples.isEmpty)

                Button {
                    Task {
                        await viewModel.connectStrava()
                    }
                } label: {
                    Label(
                        viewModel.isStravaConnected ? "CONNECTED" : (viewModel.isConnectingStrava ? "CONNECTING" : "CONNECT"),
                        systemImage: viewModel.isStravaConnected ? "checkmark.circle.fill" : "person.crop.circle.badge.plus"
                    )
                    .frame(maxWidth: .infinity)
                }
                .disabled(viewModel.isStravaConnected || viewModel.isConnectingStrava)

                Button {
                    Task {
                        await viewModel.uploadWorkoutToStrava()
                    }
                } label: {
                    Label(viewModel.isUploadingToStrava ? "UPLOADING" : "STRAVA", systemImage: "arrow.up.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(engine.samples.isEmpty || !viewModel.isStravaConnected || viewModel.isUploadingToStrava)
            }
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

private struct CockpitStatusBlock: View {
    @ObservedObject var engine: WorkoutEngine

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
        }
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
    @ObservedObject var engine: WorkoutEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CONTROL")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))

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
