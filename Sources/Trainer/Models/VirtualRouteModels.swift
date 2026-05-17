import CoreLocation
import Foundation

struct VirtualRoute: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var points: [VirtualRoutePoint]

    init(id: UUID = UUID(), name: String, points: [VirtualRoutePoint]) {
        self.id = id
        self.name = name
        self.points = points
    }

    var totalDistanceMeters: Double {
        points.last?.distanceMeters ?? 0
    }

    var elevationGainMeters: Double {
        zip(points, points.dropFirst()).reduce(0) { total, pair in
            let gain = (pair.1.elevationMeters ?? pair.0.elevationMeters ?? 0) - (pair.0.elevationMeters ?? pair.1.elevationMeters ?? 0)
            return total + max(0, gain)
        }
    }

    var hasCompleteElevation: Bool {
        points.allSatisfy { $0.elevationMeters != nil }
    }

    func replacingElevations(_ elevations: [Double?]) -> VirtualRoute {
        let updatedPoints = zip(points, elevations).map { point, elevation in
            VirtualRoutePoint(
                coordinate: point.coordinate,
                elevationMeters: elevation ?? point.elevationMeters,
                distanceMeters: point.distanceMeters
            )
        }
        return VirtualRoute(id: id, name: name, points: updatedPoints)
    }

    func location(at distanceMeters: Double) -> VirtualRouteLocation? {
        guard let first = points.first else { return nil }
        guard points.count > 1 else {
            return VirtualRouteLocation(
                coordinate: first.coordinate,
                elevationMeters: first.elevationMeters,
                distanceMeters: 0,
                grade: 0,
                progress: 0
            )
        }

        let clampedDistance = min(max(0, distanceMeters), totalDistanceMeters)
        guard clampedDistance > 0 else {
            return VirtualRouteLocation(
                coordinate: first.coordinate,
                elevationMeters: first.elevationMeters,
                distanceMeters: clampedDistance,
                grade: grade(at: clampedDistance),
                progress: 0
            )
        }

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            guard clampedDistance <= current.distanceMeters else { continue }

            let segmentDistance = max(0.1, current.distanceMeters - previous.distanceMeters)
            let segmentProgress = min(1, max(0, (clampedDistance - previous.distanceMeters) / segmentDistance))
            let coordinate = CLLocationCoordinate2D(
                latitude: previous.coordinate.latitude + ((current.coordinate.latitude - previous.coordinate.latitude) * segmentProgress),
                longitude: previous.coordinate.longitude + ((current.coordinate.longitude - previous.coordinate.longitude) * segmentProgress)
            )

            let elevation: Double?
            if let previousElevation = previous.elevationMeters, let currentElevation = current.elevationMeters {
                elevation = previousElevation + ((currentElevation - previousElevation) * segmentProgress)
            } else {
                elevation = previous.elevationMeters ?? current.elevationMeters
            }

            return VirtualRouteLocation(
                coordinate: coordinate,
                elevationMeters: elevation,
                distanceMeters: clampedDistance,
                grade: grade(at: clampedDistance),
                progress: totalDistanceMeters > 0 ? clampedDistance / totalDistanceMeters : 0
            )
        }

        guard let last = points.last else { return nil }
        return VirtualRouteLocation(
            coordinate: last.coordinate,
            elevationMeters: last.elevationMeters,
            distanceMeters: totalDistanceMeters,
            grade: 0,
            progress: 1
        )
    }

    private func grade(at distanceMeters: Double) -> Double {
        let halfWindowMeters = 45.0
        let startDistance = max(0, distanceMeters - halfWindowMeters)
        let endDistance = min(totalDistanceMeters, distanceMeters + halfWindowMeters)
        guard endDistance - startDistance >= 1,
              let startElevation = elevation(at: startDistance),
              let endElevation = elevation(at: endDistance) else {
            return 0
        }

        let distance = max(1, endDistance - startDistance)
        return ((endElevation - startElevation) / distance).clamped(to: -0.25...0.25)
    }

    private func elevation(at distanceMeters: Double) -> Double? {
        guard let first = points.first else { return nil }
        guard points.count > 1 else { return first.elevationMeters }
        let clampedDistance = min(max(0, distanceMeters), totalDistanceMeters)

        if clampedDistance <= 0 {
            return first.elevationMeters
        }

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            guard clampedDistance <= current.distanceMeters else { continue }
            guard let previousElevation = previous.elevationMeters,
                  let currentElevation = current.elevationMeters else {
                return previous.elevationMeters ?? current.elevationMeters
            }

            let segmentDistance = max(0.1, current.distanceMeters - previous.distanceMeters)
            let segmentProgress = min(1, max(0, (clampedDistance - previous.distanceMeters) / segmentDistance))
            return previousElevation + ((currentElevation - previousElevation) * segmentProgress)
        }

        return points.last?.elevationMeters
    }
}

struct VirtualRoutePoint: Codable, Equatable {
    var coordinate: CLLocationCoordinate2D
    var elevationMeters: Double?
    var distanceMeters: Double

    private enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
        case elevationMeters
        case distanceMeters
    }

    init(coordinate: CLLocationCoordinate2D, elevationMeters: Double?, distanceMeters: Double) {
        self.coordinate = coordinate
        self.elevationMeters = elevationMeters
        self.distanceMeters = distanceMeters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coordinate = CLLocationCoordinate2D(
            latitude: try container.decode(Double.self, forKey: .latitude),
            longitude: try container.decode(Double.self, forKey: .longitude)
        )
        elevationMeters = try container.decodeIfPresent(Double.self, forKey: .elevationMeters)
        distanceMeters = try container.decode(Double.self, forKey: .distanceMeters)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
        try container.encodeIfPresent(elevationMeters, forKey: .elevationMeters)
        try container.encode(distanceMeters, forKey: .distanceMeters)
    }

    static func == (lhs: VirtualRoutePoint, rhs: VirtualRoutePoint) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.elevationMeters == rhs.elevationMeters
            && lhs.distanceMeters == rhs.distanceMeters
    }
}

struct VirtualRouteLocation: Equatable {
    var coordinate: CLLocationCoordinate2D
    var elevationMeters: Double?
    var distanceMeters: Double
    var grade: Double
    var progress: Double

    static func == (lhs: VirtualRouteLocation, rhs: VirtualRouteLocation) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.elevationMeters == rhs.elevationMeters
            && lhs.distanceMeters == rhs.distanceMeters
            && lhs.grade == rhs.grade
            && lhs.progress == rhs.progress
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
