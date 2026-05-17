import SwiftUI

struct WorkoutScreen: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject var engine: WorkoutEngine
    @AppStorage("workoutScreen.chartHeightFractions")
    private var storedChartHeightFractions = "1,1,1"
    @State private var dragStartHeights: [CGFloat]?

    private let resizeHandleHeight: CGFloat = 16
    private let minimumChartHeight: CGFloat = 130
    private static let defaultChartHeightFractions: [CGFloat] = [1, 1, 1]

    var body: some View {
        HStack(spacing: 18) {
            resizableChartStack
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

    private var resizableChartStack: some View {
        GeometryReader { geometry in
            let mapHeight = engine.virtualRoute == nil ? 0 : min(260, max(190, geometry.size.height * 0.30))
            let mapSpacing: CGFloat = engine.virtualRoute == nil ? 0 : 16
            let chartTotalHeight = max(0, geometry.size.height - resizeHandleHeight * 2 - mapHeight - mapSpacing)
            let fractions = normalizedChartFractions
            let heights = fractions.map { $0 * chartTotalHeight }

            VStack(spacing: 0) {
                if engine.virtualRoute != nil {
                    VirtualRouteMapView(engine: engine)
                        .frame(height: mapHeight)
                        .padding(.bottom, mapSpacing)
                }

                heartRateChart(scale: chartScale(for: heights[0]))
                    .frame(height: heights[0])

                ChartResizeHandle()
                    .frame(height: resizeHandleHeight)
                    .gesture(resizeGesture(splitIndex: 0, chartTotalHeight: chartTotalHeight))

                cadenceChart(scale: chartScale(for: heights[1]))
                    .frame(height: heights[1])

                ChartResizeHandle()
                    .frame(height: resizeHandleHeight)
                    .gesture(resizeGesture(splitIndex: 1, chartTotalHeight: chartTotalHeight))

                powerChart(scale: chartScale(for: heights[2]))
                    .frame(height: heights[2])
            }
        }
    }

    private var normalizedChartFractions: [CGFloat] {
        let total = chartHeightFractions.reduce(0, +)
        guard total > 0 else { return [1 / 3, 1 / 3, 1 / 3] }
        return chartHeightFractions.map { $0 / total }
    }

    private var chartHeightFractions: [CGFloat] {
        get {
            Self.decodeChartHeightFractions(storedChartHeightFractions)
        }
        nonmutating set {
            storedChartHeightFractions = Self.encodeChartHeightFractions(newValue)
        }
    }

    private func resizeGesture(splitIndex: Int, chartTotalHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                resizeCharts(
                    splitIndex: splitIndex,
                    chartTotalHeight: chartTotalHeight,
                    translation: value.translation.height
                )
            }
            .onEnded { _ in
                dragStartHeights = nil
            }
    }

    private func resizeCharts(splitIndex: Int, chartTotalHeight: CGFloat, translation: CGFloat) {
        guard chartTotalHeight > 0, splitIndex >= 0, splitIndex < 2 else { return }

        let currentHeights = normalizedChartFractions.map { $0 * chartTotalHeight }
        if dragStartHeights == nil {
            dragStartHeights = currentHeights
        }

        guard var updatedHeights = dragStartHeights else { return }
        let upperIndex = splitIndex
        let lowerIndex = splitIndex + 1
        let pairHeight = updatedHeights[upperIndex] + updatedHeights[lowerIndex]
        let minimumHeight = min(minimumChartHeight, max(1, pairHeight / 2 - 1))
        let upperHeight = min(
            max(updatedHeights[upperIndex] + translation, minimumHeight),
            pairHeight - minimumHeight
        )

        updatedHeights[upperIndex] = upperHeight
        updatedHeights[lowerIndex] = pairHeight - upperHeight
        chartHeightFractions = updatedHeights.map { $0 / chartTotalHeight }
    }

    private func chartScale(for height: CGFloat) -> CGFloat {
        min(max(height / 185, 0.72), 1.65)
    }

    private static func decodeChartHeightFractions(_ value: String) -> [CGFloat] {
        let fractions = value
            .split(separator: ",")
            .compactMap { part -> CGFloat? in
                guard let value = Double(part) else { return nil }
                return CGFloat(value)
            }

        guard fractions.count == 3, fractions.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            return defaultChartHeightFractions
        }

        return fractions
    }

    private static func encodeChartHeightFractions(_ fractions: [CGFloat]) -> String {
        let safeFractions = fractions.count == 3 ? fractions : defaultChartHeightFractions
        return safeFractions
            .map { String(format: "%.5f", Double($0)) }
            .joined(separator: ",")
    }

    private func heartRateChart(scale: CGFloat) -> some View {
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
            plannedTarget: { step, _, elapsed in step.target(at: elapsed).heartRateBPM },
            chartScale: scale
        )
    }

    private func cadenceChart(scale: CGFloat) -> some View {
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
            plannedTarget: { step, _, elapsed in step.target(at: elapsed).cadenceRPM },
            chartScale: scale
        )
    }

    private func powerChart(scale: CGFloat) -> some View {
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
            plannedTarget: { step, ftp, elapsed in step.target(at: elapsed).resolvedPowerWatts(ftp: ftp) },
            chartScale: scale
        )
    }
}

private struct ChartResizeHandle: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.clear)

            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 72, height: 4)
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                }
        }
        .contentShape(Rectangle())
        .help("Drag to resize adjacent graphs")
    }
}
