import MapKit
import SwiftUI

struct VirtualRouteMapView: View {
    @ObservedObject var engine: WorkoutEngine
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var lastCameraUpdateDistance: Double = -.greatestFiniteMagnitude

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let route = engine.virtualRoute {
                Map(position: $cameraPosition) {
                    MapPolyline(coordinates: route.points.map(\.coordinate))
                        .stroke(routeLineColor, lineWidth: 5)

                    if let location = engine.currentVirtualRouteLocation {
                        Annotation("", coordinate: location.coordinate) {
                            ZStack {
                                Circle()
                                    .fill(TrainerTheme.Status.time.opacity(0.26))
                                    .frame(width: 30, height: 30)
                                Circle()
                                    .fill(TrainerTheme.Status.time)
                                    .frame(width: 12, height: 12)
                                    .overlay {
                                        Circle()
                                            .stroke(.white.opacity(0.88), lineWidth: 2)
                                    }
                            }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .onAppear {
                    updateCamera(for: route, force: true)
                }
                .onChange(of: route.id) { _, _ in
                    updateCamera(for: route, force: true)
                }
                .onChange(of: engine.state) { _, _ in
                    updateCamera(for: route, force: true)
                }
                .onChange(of: engine.currentVirtualRouteLocation) { _, _ in
                    updateCamera(for: route)
                }
            }

            routeStats
                .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(TrainerTheme.Surface.separator, lineWidth: 1)
        )
    }

    private var routeStats: some View {
        HStack(spacing: 8) {
            RouteStatBadge(title: "Route", value: routeDistanceText, icon: "map")
            RouteStatBadge(title: "Done", value: progressText, icon: "location.fill")
            RouteStatBadge(title: "Grade", value: gradeText, icon: "angle")
            RouteStatBadge(title: "Speed", value: WorkoutFormatters.speed(engine.currentVirtualSpeedMetersPerSecond), icon: "speedometer")
        }
    }

    private var routeDistanceText: String {
        guard let route = engine.virtualRoute else { return "--" }
        return WorkoutFormatters.distance(route.totalDistanceMeters)
    }

    private var progressText: String {
        guard let location = engine.currentVirtualRouteLocation else { return "--" }
        return "\(Int((location.progress * 100).rounded()))%"
    }

    private var gradeText: String {
        guard let location = engine.currentVirtualRouteLocation else { return "--" }
        return WorkoutFormatters.grade(location.grade)
    }

    private var routeLineColor: Color {
        engine.state == .running ? TrainerTheme.Control.stop : TrainerTheme.Status.time
    }

    private func updateCamera(for route: VirtualRoute, force: Bool = false) {
        guard engine.state == .running,
              let location = engine.currentVirtualRouteLocation else {
            lastCameraUpdateDistance = -.greatestFiniteMagnitude
            cameraPosition = .region(route.coordinateRegion)
            return
        }

        guard force || abs(location.distanceMeters - lastCameraUpdateDistance) >= 20 else { return }
        lastCameraUpdateDistance = location.distanceMeters
        cameraPosition = .region(
            MKCoordinateRegion(
                center: location.coordinate,
                span: route.followSpan
            )
        )
    }
}

private struct RouteStatBadge: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(TrainerTheme.Surface.textTertiary)
                Text(value)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(TrainerTheme.Surface.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.black.opacity(0.66), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        )
    }
}

private extension VirtualRoute {
    var coordinateRegion: MKCoordinateRegion {
        let coordinates = points.map(\.coordinate)
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minimumLatitude = latitudes.min() ?? 0
        let maximumLatitude = latitudes.max() ?? 0
        let minimumLongitude = longitudes.min() ?? 0
        let maximumLongitude = longitudes.max() ?? 0
        let center = CLLocationCoordinate2D(
            latitude: (minimumLatitude + maximumLatitude) / 2,
            longitude: (minimumLongitude + maximumLongitude) / 2
        )
        let latitudeDelta = max(0.01, (maximumLatitude - minimumLatitude) * 1.28)
        let longitudeDelta = max(0.01, (maximumLongitude - minimumLongitude) * 1.28)

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }

    var followSpan: MKCoordinateSpan {
        let overview = coordinateRegion.span
        return MKCoordinateSpan(
            latitudeDelta: min(max(overview.latitudeDelta * 0.12, 0.006), 0.025),
            longitudeDelta: min(max(overview.longitudeDelta * 0.12, 0.006), 0.025)
        )
    }
}
