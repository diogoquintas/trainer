import CoreLocation
import Foundation

final class GPXRouteParser: NSObject, XMLParserDelegate {
    private var parsedName: String?
    private var parsedPoints: [ParsedPoint] = []
    private var currentPoint: ParsedPoint?
    private var currentText = ""
    private var isReadingRouteName = false

    func parseRoute(from data: Data, fallbackName: String) throws -> VirtualRoute {
        parsedName = nil
        parsedPoints = []
        currentPoint = nil
        currentText = ""
        isReadingRouteName = false

        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw GPXRouteParserError.invalidGPX(parser.parserError?.localizedDescription)
        }

        let routeName = parsedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let points = makeRoutePoints(from: parsedPoints)
        guard points.count >= 2 else {
            throw GPXRouteParserError.notEnoughPoints
        }

        return VirtualRoute(
            name: routeName?.isEmpty == false ? routeName! : fallbackName,
            points: points
        )
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentText = ""

        switch elementName.lowercased() {
        case "trkpt", "rtept":
            guard let latitude = attributeDict["lat"].flatMap(Double.init),
                  let longitude = attributeDict["lon"].flatMap(Double.init) else {
                currentPoint = nil
                return
            }
            currentPoint = ParsedPoint(latitude: latitude, longitude: longitude, elevationMeters: nil)
        case "name":
            isReadingRouteName = currentPoint == nil && parsedName == nil
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName.lowercased() {
        case "ele":
            currentPoint?.elevationMeters = Double(currentText.trimmingCharacters(in: .whitespacesAndNewlines))
        case "name":
            if isReadingRouteName {
                parsedName = currentText
                isReadingRouteName = false
            }
        case "trkpt", "rtept":
            if let currentPoint {
                parsedPoints.append(currentPoint)
            }
            self.currentPoint = nil
        default:
            break
        }

        currentText = ""
    }

    private func makeRoutePoints(from parsedPoints: [ParsedPoint]) -> [VirtualRoutePoint] {
        var distanceMeters = 0.0
        var previousLocation: CLLocation?

        return parsedPoints.map { point in
            let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
            if let previousLocation {
                distanceMeters += previousLocation.distance(from: location)
            }
            previousLocation = location

            return VirtualRoutePoint(
                coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude),
                elevationMeters: point.elevationMeters,
                distanceMeters: distanceMeters
            )
        }
    }
}

private struct ParsedPoint {
    var latitude: Double
    var longitude: Double
    var elevationMeters: Double?
}

enum GPXRouteParserError: LocalizedError {
    case invalidGPX(String?)
    case notEnoughPoints

    var errorDescription: String? {
        switch self {
        case .invalidGPX(let message):
            message.map { "Invalid GPX route: \($0)" } ?? "Invalid GPX route."
        case .notEnoughPoints:
            "The route needs at least two GPX track or route points."
        }
    }
}
