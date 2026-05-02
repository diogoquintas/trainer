import Foundation

final class DeferredStravaService: StravaServicing {
    func uploadActivity(fileURL: URL) async throws {
        throw StravaServiceError.notImplemented
    }
}

enum StravaServiceError: LocalizedError {
    case notImplemented

    var errorDescription: String? {
        "Strava upload is intentionally deferred until after local export, FIT/TCX, and OAuth are designed."
    }
}
