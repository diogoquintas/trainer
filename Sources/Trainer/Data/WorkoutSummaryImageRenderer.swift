import AppKit
import SwiftUI

@MainActor
enum WorkoutSummaryImageRenderer {
    static func renderPNG(workout: Workout, samples: [WorkoutSample], size: CGSize = CGSize(width: 1600, height: 900)) throws -> Data {
        guard !samples.isEmpty else {
            throw WorkoutSummaryImageError.noSamples
        }

        let summary = WorkoutSummary(workout: workout, samples: samples)
        let view = WorkoutSummaryCard(summary: summary)
            .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let pngData = image.pngData else {
            throw WorkoutSummaryImageError.renderFailed
        }

        return pngData
    }
}

enum WorkoutSummaryImageError: LocalizedError {
    case noSamples
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .noSamples:
            "There are no workout samples to render."
        case .renderFailed:
            "Could not render the workout summary image."
        }
    }
}

private struct WorkoutSummary {
    let workoutName: String
    let description: String
    let date: Date
    let duration: TimeInterval
    let power: MetricSummary
    let cadence: MetricSummary
    let heartRate: MetricSummary
    let samples: [WorkoutSample]

    init(workout: Workout, samples: [WorkoutSample]) {
        workoutName = workout.name
        description = workout.description ?? "Indoor training session"
        date = samples.first?.timestamp ?? Date()
        duration = samples.last?.elapsed ?? 0
        power = MetricSummary(values: samples.compactMap(\.powerWatts))
        cadence = MetricSummary(values: samples.compactMap(\.cadenceRPM))
        heartRate = MetricSummary(values: samples.compactMap(\.heartRateBPM))
        self.samples = samples
    }
}

private struct MetricSummary {
    let average: Int?
    let minimum: Int?
    let maximum: Int?

    init(values: [Int]) {
        guard !values.isEmpty else {
            average = nil
            minimum = nil
            maximum = nil
            return
        }

        average = Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
        minimum = values.min()
        maximum = values.max()
    }
}

private struct WorkoutSummaryCard: View {
    let summary: WorkoutSummary

    var body: some View {
        ZStack {
            background

            VStack(alignment: .leading, spacing: 30) {
                header

                VStack(spacing: 22) {
                    MetricSummaryRow(
                        title: "Power",
                        unit: "W",
                        color: .orange,
                        summary: summary.power,
                        samples: summary.samples,
                        actual: { $0.powerWatts },
                        target: { $0.targetPowerWatts }
                    )
                    MetricSummaryRow(
                        title: "Cadence",
                        unit: "rpm",
                        color: .cyan,
                        summary: summary.cadence,
                        samples: summary.samples,
                        actual: { $0.cadenceRPM },
                        target: { $0.targetCadenceRPM }
                    )
                    MetricSummaryRow(
                        title: "Heart Rate",
                        unit: "bpm",
                        color: .red,
                        summary: summary.heartRate,
                        samples: summary.samples,
                        actual: { $0.heartRateBPM },
                        target: { $0.targetHeartRateBPM }
                    )
                }
            }
            .padding(64)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text(summary.workoutName)
                    .font(.system(size: 58, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .foregroundStyle(.white)
                Text(summary.description)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(.white.opacity(0.58))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                Text(summary.date, style: .date)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                Text(WorkoutFormatters.duration(summary.duration))
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.013, green: 0.016, blue: 0.022),
                Color(red: 0.018, green: 0.026, blue: 0.032)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(SummaryBackgroundTexture())
    }
}

private struct SummaryBackgroundTexture: View {
    var body: some View {
        Canvas { context, size in
            for y in stride(from: 80, through: Int(size.height), by: 96) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: CGFloat(y)))
                path.addLine(to: CGPoint(x: size.width, y: CGFloat(y)))
                context.stroke(path, with: .color(.white.opacity(0.022)), lineWidth: 1)
            }

            for x in stride(from: 96, through: Int(size.width), by: 128) {
                var path = Path()
                path.move(to: CGPoint(x: CGFloat(x), y: 0))
                path.addLine(to: CGPoint(x: CGFloat(x), y: size.height))
                context.stroke(path, with: .color(.white.opacity(0.012)), lineWidth: 1)
            }
        }
    }
}

private struct MetricSummaryRow: View {
    let title: String
    let unit: String
    let color: Color
    let summary: MetricSummary
    let samples: [WorkoutSample]
    let actual: (WorkoutSample) -> Int?
    let target: (WorkoutSample) -> Int?

    var body: some View {
        HStack(spacing: 28) {
            SummaryChart(
                title: title,
                unit: unit,
                color: color,
                summary: summary,
                samples: samples,
                actual: actual,
                target: target
            )

            AverageBlock(
                title: "Avg \(title)",
                value: formatted(summary.average),
                unit: unit,
                color: color
            )
            .frame(width: 190)
        }
    }

    private func formatted(_ value: Int?) -> String {
        guard let value else { return "--" }
        return "\(value)"
    }
}

private struct AverageBlock: View {
    let title: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(color)
            HStack(alignment: .lastTextBaseline, spacing: 7) {
                Text(value)
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .foregroundStyle(.white)
                Text(unit)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.54))
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

private struct SummaryChart: View {
    let title: String
    let unit: String
    let color: Color
    let summary: MetricSummary
    let samples: [WorkoutSample]
    let actual: (WorkoutSample) -> Int?
    let target: (WorkoutSample) -> Int?

    var body: some View {
        ZStack {
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: 210, dy: 26)
                drawGrid(in: rect, context: &context)

                var clippedContext = context
                clippedContext.clip(to: Path(rect))
                clippedContext.stroke(
                    path(for: targetPoints, in: rect),
                    with: .color(color.opacity(0.42)),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [10, 8])
                )
                clippedContext.stroke(
                    path(for: actualPoints, in: rect),
                    with: .color(color),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
                )
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title.uppercased())
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(color)
                    Text(unit)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.48))
                }
                .frame(width: 160, alignment: .leading)

                Spacer()

                VStack(alignment: .trailing, spacing: 34) {
                    RangeValue(label: "MAX", value: formatted(summary.maximum))
                    RangeValue(label: "MIN", value: formatted(summary.minimum))
                }
                .frame(width: 96, alignment: .trailing)
            }
            .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 194)
        .background(.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.30), lineWidth: 1)
        )
    }

    private var actualPoints: [SummaryPlotPoint] {
        samples.compactMap { sample in
            guard let value = actual(sample) else { return nil }
            return SummaryPlotPoint(elapsed: sample.elapsed, value: Double(value))
        }
    }

    private var targetPoints: [SummaryPlotPoint] {
        samples.compactMap { sample in
            guard let value = target(sample) else { return nil }
            return SummaryPlotPoint(elapsed: sample.elapsed, value: Double(value))
        }
    }

    private var xDomain: ClosedRange<Double> {
        0...max(1, samples.last?.elapsed ?? 1)
    }

    private var yDomain: ClosedRange<Double> {
        let values = (actualPoints + targetPoints).map(\.value)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...1
        }

        let padding = max(10, (maxValue - minValue) * 0.22)
        return max(0, minValue - padding)...(maxValue + padding)
    }

    private func formatted(_ value: Int?) -> String {
        guard let value else { return "--" }
        return "\(value)"
    }

    private func drawGrid(in rect: CGRect, context: inout GraphicsContext) {
        for index in 0...4 {
            let progress = Double(index) / 4
            let y = rect.minY + rect.height * progress
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.stroke(path, with: .color(.white.opacity(0.075)), style: StrokeStyle(lineWidth: 1, dash: [5, 9]))
        }

        for index in 0...5 {
            let progress = Double(index) / 5
            let x = rect.minX + rect.width * progress
            var path = Path()
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            context.stroke(path, with: .color(.white.opacity(0.040)), lineWidth: 1)
        }
    }

    private func path(for points: [SummaryPlotPoint], in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }

        path.move(to: screenPoint(for: first, in: rect))
        for point in points.dropFirst() {
            path.addLine(to: screenPoint(for: point, in: rect))
        }

        return path
    }

    private func screenPoint(for point: SummaryPlotPoint, in rect: CGRect) -> CGPoint {
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

private struct RangeValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.38))
            Text(value)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.76))
        }
    }
}

private struct SummaryPlotPoint {
    let elapsed: TimeInterval
    let value: Double
}

private extension NSImage {
    var pngData: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}
