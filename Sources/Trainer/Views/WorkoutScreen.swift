import SwiftUI

struct WorkoutScreen: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject var engine: WorkoutEngine

    var body: some View {
        HStack(spacing: 18) {
            VStack(spacing: 18) {
                WorkoutHeaderView(engine: engine)

                MetricChartView(
                    title: "Heart Rate",
                    unit: "bpm",
                    symbolName: "heart.fill",
                    actualColor: .red,
                    targetColor: .mint,
                    workout: engine.workout,
                    workoutState: engine.state,
                    elapsed: engine.elapsed,
                    samples: engine.chartSamples,
                    currentValue: engine.latestHeartRateReading?.bpm,
                    targetValue: engine.currentTarget.heartRateBPM,
                    actual: { $0.heartRateBPM },
                    plannedTarget: { step, _ in step.target.heartRateBPM }
                )

                MetricChartView(
                    title: "Cadence",
                    unit: "rpm",
                    symbolName: "metronome.fill",
                    actualColor: .cyan,
                    targetColor: .green,
                    workout: engine.workout,
                    workoutState: engine.state,
                    elapsed: engine.elapsed,
                    samples: engine.chartSamples,
                    currentValue: engine.latestTrainerReading.cadenceRPM,
                    targetValue: engine.currentTarget.cadenceRPM,
                    actual: { $0.cadenceRPM },
                    plannedTarget: { step, _ in step.target.cadenceRPM }
                )

                MetricChartView(
                    title: "Power",
                    unit: "W",
                    symbolName: "bolt.fill",
                    actualColor: .orange,
                    targetColor: .purple,
                    workout: engine.workout,
                    workoutState: engine.state,
                    elapsed: engine.elapsed,
                    samples: engine.chartSamples,
                    currentValue: engine.latestTrainerReading.powerWatts,
                    targetValue: engine.currentTarget.resolvedPowerWatts(ftp: engine.workout.ftp),
                    actual: { $0.powerWatts },
                    plannedTarget: { step, ftp in step.target.resolvedPowerWatts(ftp: ftp) }
                )
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            SidePanelView(engine: engine)
                .environmentObject(viewModel)
                .frame(width: 280)
                .padding(.vertical, 22)
                .padding(.trailing, 22)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.015, green: 0.018, blue: 0.025),
                    Color(red: 0.025, green: 0.035, blue: 0.045)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

private struct WorkoutHeaderView: View {
    @ObservedObject var engine: WorkoutEngine

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(engine.workout.name)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(engine.currentStep?.name ?? "Ready")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(WorkoutFormatters.duration(engine.elapsed))
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("\(WorkoutFormatters.duration(engine.timeRemainingInStep)) LEFT")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.cyan)
            }
            Text(engine.state.rawValue.capitalized)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(engine.state == .running ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(engine.state == .running ? Color.green : Color.white.opacity(0.12), in: Capsule())
        }
    }
}
