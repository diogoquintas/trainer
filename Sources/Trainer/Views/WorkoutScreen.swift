import SwiftUI

struct WorkoutScreen: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject var engine: WorkoutEngine

    var body: some View {
        HStack(spacing: 18) {
            VStack(spacing: 18) {
                MetricChartView(
                    title: "Heart Rate",
                    unit: "bpm",
                    symbolName: "heart.fill",
                    metricColor: TrainerTheme.Metric.heartRate,
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
                    metricColor: TrainerTheme.Metric.cadence,
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
                    metricColor: TrainerTheme.Metric.power,
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
        .background(TrainerTheme.Surface.appBackground)
    }
}
