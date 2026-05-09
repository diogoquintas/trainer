import SwiftUI

struct MetricChartView: View {
    let title: String
    let unit: String
    let symbolName: String
    let metricColor: Color
    let workout: Workout
    let workoutState: WorkoutState
    let elapsed: TimeInterval
    let samples: [WorkoutSample]
    let currentValue: Int?
    let targetValue: Int?
    let actual: (WorkoutSample) -> Int?
    let plannedTarget: (WorkoutStep, Int) -> Int?

    private var visibleSamples: ArraySlice<WorkoutSample> {
        samples.suffix(1_800)
    }

    private var visibleActualSamples: [WorkoutSample] {
        let domain = xDomain
        return visibleSamples.filter { domain.contains($0.elapsed) }
    }

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: symbolName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(metricColor)
                    Text(title.uppercased())
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(TrainerTheme.Surface.textPrimary)
                    Spacer()
                    LegendDot(color: metricColor, label: "LIVE")
                    LegendDot(color: metricColor.opacity(0.46), label: "TARGET")
                }

                CockpitLinePlot(
                    actualPoints: visibleActualPoints,
                    targetPoints: visibleTargetPoints,
                    xDomain: xDomain,
                    yDomain: yDomain,
                    metricColor: metricColor
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            MetricReadout(
                unit: unit,
                metricColor: metricColor,
                currentValue: currentValue,
                targetValue: targetValue
            )
            .frame(width: 190)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 185)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(metricColor.opacity(0.50), lineWidth: 1)
        )
        .shadow(color: metricColor.opacity(0.16), radius: 18, x: 0, y: 8)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var panelBackground: LinearGradient {
        TrainerTheme.Surface.panel
    }

    private var xDomain: ClosedRange<Double> {
        guard workoutState != .stopped && workoutState != .paused else {
            return 0...max(45, workout.totalDuration)
        }

        let pastWindow: TimeInterval = 35
        let futureWindow: TimeInterval = 25
        return (elapsed - pastWindow)...(elapsed + futureWindow)
    }

    private var yDomain: ClosedRange<Double> {
        let actualValues = visibleActualPoints.map(\.value)
        let targetValues = visibleTargetPoints.map(\.value)
        let values = actualValues + targetValues
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...200
        }

        let padding = max(12, (maxValue - minValue) * 0.22)
        return max(0, minValue - padding)...(maxValue + padding)
    }

    private var visibleActualPoints: [PlotPoint] {
        visibleActualSamples.compactMap { sample in
            guard let value = actual(sample) else { return nil }
            return PlotPoint(elapsed: sample.elapsed, value: Double(value))
        }
    }

    private var visibleTargetPoints: [PlotPoint] {
        visiblePlannedTargetPoints.map { point in
            PlotPoint(elapsed: point.elapsed, value: Double(point.value))
        }
    }

    private var visiblePlannedTargetPoints: [PlannedTargetPoint] {
        var points: [PlannedTargetPoint] = []
        let domain = xDomain
        var elapsed: TimeInterval = 0

        for (index, step) in workout.steps.enumerated() {
            guard let value = plannedTarget(step, workout.ftp) else {
                elapsed += step.duration
                continue
            }

            let end = elapsed + step.duration
            let visibleStart = max(elapsed, domain.lowerBound)
            let visibleEnd = min(end, domain.upperBound)

            if visibleStart <= visibleEnd, end >= domain.lowerBound, elapsed <= domain.upperBound {
                points.append(PlannedTargetPoint(elapsed: visibleStart, value: value, stepIndex: index, edge: .start))
                points.append(PlannedTargetPoint(elapsed: visibleEnd, value: value, stepIndex: index, edge: .end))
            }

            elapsed = end
        }

        return points
    }
}

private struct PlotPoint: Hashable {
    let elapsed: TimeInterval
    let value: Double
}

private struct CockpitLinePlot: View {
    let actualPoints: [PlotPoint]
    let targetPoints: [PlotPoint]
    let xDomain: ClosedRange<Double>
    let yDomain: ClosedRange<Double>
    let metricColor: Color

    var body: some View {
        Canvas { context, size in
            let plotRect = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 8)
            guard plotRect.width > 1, plotRect.height > 1 else { return }

            drawGrid(in: plotRect, context: &context)

            var clippedContext = context
            clippedContext.clip(to: Path(plotRect))

            let targetPath = path(for: targetPoints, in: plotRect)
            clippedContext.stroke(
                targetPath,
                with: .color(metricColor.opacity(0.46)),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [7, 5])
            )

            let actualPath = path(for: actualPoints, in: plotRect)
            clippedContext.stroke(
                actualPath,
                with: .color(metricColor.opacity(0.24)),
                style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round)
            )
            clippedContext.stroke(
                actualPath,
                with: .color(metricColor),
                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
            )
        }
        .drawingGroup(opaque: false)
    }

    private func drawGrid(in rect: CGRect, context: inout GraphicsContext) {
        let horizontalLines = 4
        let verticalLines = 5

        for index in 0...horizontalLines {
            let progress = Double(index) / Double(horizontalLines)
            let y = rect.minY + rect.height * progress
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.stroke(
                path,
                with: .color(Color.white.opacity(index == horizontalLines ? 0.18 : 0.10)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 7])
            )
        }

        for index in 0...verticalLines {
            let progress = Double(index) / Double(verticalLines)
            let x = rect.minX + rect.width * progress
            var path = Path()
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            context.stroke(path, with: .color(Color.white.opacity(0.06)), lineWidth: 1)
        }
    }

    private func path(for points: [PlotPoint], in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }

        path.move(to: screenPoint(for: first, in: rect))
        for point in points.dropFirst() {
            path.addLine(to: screenPoint(for: point, in: rect))
        }

        return path
    }

    private func screenPoint(for point: PlotPoint, in rect: CGRect) -> CGPoint {
        let xSpan = max(0.001, xDomain.upperBound - xDomain.lowerBound)
        let ySpan = max(0.001, yDomain.upperBound - yDomain.lowerBound)
        let xProgress = (point.elapsed - xDomain.lowerBound) / xSpan
        let yProgress = (point.value - yDomain.lowerBound) / ySpan
        return CGPoint(
            x: rect.minX + rect.width * xProgress,
            y: rect.maxY - rect.height * yProgress
        )
    }
}

private struct PlannedTargetPoint: Identifiable {
    enum Edge: String {
        case start
        case end
    }

    let elapsed: TimeInterval
    let value: Int
    let stepIndex: Int
    let edge: Edge

    var id: String {
        "\(stepIndex)-\(edge.rawValue)-\(elapsed)-\(value)"
    }
}

private struct MetricReadout: View {
    let unit: String
    let metricColor: Color
    let currentValue: Int?
    let targetValue: Int?

    var body: some View {
        VStack(alignment: .trailing, spacing: 16) {
            VStack(alignment: .trailing, spacing: 0) {
                Text("LIVE")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(metricColor)
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(WorkoutFormatters.number(currentValue))
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.55)
                        .foregroundStyle(metricColor)
                        .frame(width: 130, alignment: .trailing)
                    Text(unit)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(TrainerTheme.Surface.textSecondary)
                        .frame(width: 36, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            VStack(alignment: .trailing, spacing: 0) {
                Text("TARGET")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(metricColor.opacity(0.72))
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(WorkoutFormatters.number(targetValue))
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(metricColor.opacity(0.72))
                        .frame(width: 130, alignment: .trailing)
                    Text(unit)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(TrainerTheme.Surface.textSecondary)
                        .frame(width: 36, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .shadow(color: color.opacity(0.55), radius: 6)
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(TrainerTheme.Surface.textSecondary)
        }
    }
}
