import CoreLocation
import Foundation

struct OpenMeteoElevationService {
    private let batchSize = 100

    func enrichedRoute(_ route: VirtualRoute) async throws -> VirtualRoute {
        var elevations: [Double?] = []
        elevations.reserveCapacity(route.points.count)

        for batch in route.points.chunked(into: batchSize) {
            elevations.append(contentsOf: try await fetchElevations(for: batch))
        }

        return route.replacingElevations(elevations)
    }

    private func fetchElevations(for points: ArraySlice<VirtualRoutePoint>) async throws -> [Double?] {
        let latitudes = points
            .map { String(format: "%.6f", $0.coordinate.latitude) }
            .joined(separator: ",")
        let longitudes = points
            .map { String(format: "%.6f", $0.coordinate.longitude) }
            .joined(separator: ",")

        guard let url = URL(string: "https://api.open-meteo.com/v1/elevation?latitude=\(latitudes)&longitude=\(longitudes)") else {
            throw OpenMeteoElevationError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw OpenMeteoElevationError.requestFailed
        }

        let payload = try JSONDecoder().decode(OpenMeteoElevationResponse.self, from: data)
        guard payload.elevation.count == points.count else {
            throw OpenMeteoElevationError.unexpectedResponse
        }

        return payload.elevation
    }
}

private struct OpenMeteoElevationResponse: Decodable {
    let elevation: [Double?]
}

enum OpenMeteoElevationError: LocalizedError {
    case invalidURL
    case requestFailed
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Could not build the elevation request."
        case .requestFailed:
            "The elevation service did not return a successful response."
        case .unexpectedResponse:
            "The elevation service returned an unexpected response."
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [ArraySlice<Element>] {
        guard size > 0 else { return [self[...]] }
        return stride(from: startIndex, to: endIndex, by: size).map { start in
            let end = index(start, offsetBy: size, limitedBy: endIndex) ?? endIndex
            return self[start..<end]
        }
    }
}
