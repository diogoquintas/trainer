import AppKit
import AuthenticationServices
import Foundation

struct StravaUpload: Decodable {
    let id: Int
    let externalID: String?
    let error: String?
    let status: String?
    let activityID: Int?

    private enum CodingKeys: String, CodingKey {
        case id
        case externalID = "external_id"
        case error
        case status
        case activityID = "activity_id"
    }
}

final class StravaService: StravaServicing {
    private let client: URLSession
    private let credentials: StravaCredentials
    private let tokenStore: StravaTokenStore
    private let decoder = JSONDecoder()
    private let presentationProvider = StravaAuthenticationPresentationProvider()
    private var authSession: ASWebAuthenticationSession?

    init(
        client: URLSession = .shared,
        credentials: StravaCredentials = .environment(),
        tokenStore: StravaTokenStore = UserDefaultsStravaTokenStore()
    ) {
        self.client = client
        self.credentials = credentials
        self.tokenStore = tokenStore
    }

    var isConnected: Bool {
        tokenStore.refreshToken != nil || credentials.refreshToken != nil
    }

    func connect() async throws {
        guard let clientID = credentials.clientID, let clientSecret = credentials.clientSecret else {
            throw StravaServiceError.missingCredentials
        }

        let state = UUID().uuidString
        var components = URLComponents(url: StravaEndpoint.authorize.url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: StravaOAuth.callbackURL.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: "activity:write"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let url = components?.url else {
            throw StravaServiceError.invalidRequest
        }

        let callbackURL = try await authenticate(url: url)
        let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        let queryItems = callbackComponents?.queryItems ?? []

        if let error = queryItems.firstValue(named: "error") {
            throw StravaServiceError.authorizationDenied(error)
        }

        guard queryItems.firstValue(named: "state") == state else {
            throw StravaServiceError.invalidAuthorizationState
        }

        guard let code = queryItems.firstValue(named: "code") else {
            throw StravaServiceError.missingAuthorizationCode
        }

        let token = try await exchangeAuthorizationCode(code, clientID: clientID, clientSecret: clientSecret)
        tokenStore.saveRefreshToken(token.refreshToken)
    }

    func uploadActivity(fileURL: URL, name: String, description: String?) async throws -> StravaUpload {
        let accessToken = try await accessToken()
        let externalID = fileURL.lastPathComponent
        let hasGPSData = try tcxContainsGPSData(fileURL)
        var formData = MultipartFormData()
            .field(named: "data_type", value: "tcx")
            .field(named: "name", value: name)
            .field(named: "description", value: description ?? "")
            .field(named: "external_id", value: externalID)

        if hasGPSData {
            formData = formData.field(named: "sport_type", value: "Ride")
        } else {
            formData = formData.field(named: "trainer", value: "1")
        }

        let body = try formData
            .file(named: "file", fileURL: fileURL, mimeType: "application/vnd.garmin.tcx+xml")
            .encode()

        var request = URLRequest(url: StravaEndpoint.uploads.url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(body.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data

        let (data, response) = try await client.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(StravaUpload.self, from: data)
    }

    private func tcxContainsGPSData(_ fileURL: URL) throws -> Bool {
        let data = try Data(contentsOf: fileURL)
        guard let xml = String(data: data, encoding: .utf8) else { return false }
        return xml.contains("<Position>")
            && xml.contains("<LatitudeDegrees>")
            && xml.contains("<LongitudeDegrees>")
    }

    private func accessToken() async throws -> String {
        guard let clientID = credentials.clientID, let clientSecret = credentials.clientSecret else {
            throw StravaServiceError.missingCredentials
        }

        guard let refreshToken = tokenStore.refreshToken ?? credentials.refreshToken else {
            throw StravaServiceError.missingRefreshToken
        }

        var components = URLComponents(url: StravaEndpoint.oauthToken.url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken)
        ]

        guard let url = components?.url else {
            throw StravaServiceError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (data, response) = try await client.data(for: request)
        try validate(response: response, data: data)
        let token = try decoder.decode(StravaTokenResponse.self, from: data)
        tokenStore.saveRefreshToken(token.refreshToken)
        return token.accessToken
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StravaServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? decoder.decode(StravaFault.self, from: data).message)
                ?? String(data: data, encoding: .utf8)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw StravaServiceError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }
    }

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: StravaOAuth.callbackScheme
            ) { callbackURL, error in
                self.authSession = nil
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: StravaServiceError.missingAuthorizationCode)
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = presentationProvider
            session.prefersEphemeralWebBrowserSession = false
            authSession = session
            if !session.start() {
                authSession = nil
                continuation.resume(throwing: StravaServiceError.authorizationSessionFailed)
            }
        }
    }

    private func exchangeAuthorizationCode(
        _ code: String,
        clientID: String,
        clientSecret: String
    ) async throws -> StravaTokenResponse {
        var components = URLComponents(url: StravaEndpoint.oauthToken.url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code)
        ]

        guard let url = components?.url else {
            throw StravaServiceError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (data, response) = try await client.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(StravaTokenResponse.self, from: data)
    }
}

struct StravaCredentials {
    let clientID: String?
    let clientSecret: String?
    let refreshToken: String?

    static func environment() -> StravaCredentials {
        let environment = ProcessInfo.processInfo.environment
        let defaults = UserDefaults.standard
        return StravaCredentials(
            clientID: environment["STRAVA_CLIENT_ID"] ?? defaults.string(forKey: "strava.clientID"),
            clientSecret: environment["STRAVA_CLIENT_SECRET"] ?? defaults.string(forKey: "strava.clientSecret"),
            refreshToken: environment["STRAVA_REFRESH_TOKEN"] ?? defaults.string(forKey: "strava.refreshToken")
        )
    }
}

protocol StravaTokenStore {
    var refreshToken: String? { get }
    func saveRefreshToken(_ refreshToken: String)
}

final class UserDefaultsStravaTokenStore: StravaTokenStore {
    private let key = "strava.refreshToken"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var refreshToken: String? {
        defaults.string(forKey: key)
    }

    func saveRefreshToken(_ refreshToken: String) {
        defaults.set(refreshToken, forKey: key)
    }
}

enum StravaServiceError: LocalizedError {
    case missingCredentials
    case missingRefreshToken
    case invalidRequest
    case invalidResponse
    case authorizationDenied(String)
    case authorizationSessionFailed
    case invalidAuthorizationState
    case missingAuthorizationCode
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "Set STRAVA_CLIENT_ID and STRAVA_CLIENT_SECRET before uploading to Strava."
        case .missingRefreshToken:
            "Set STRAVA_REFRESH_TOKEN once, or connect Strava to provide an upload refresh token."
        case .invalidRequest:
            "Could not build the Strava request."
        case .invalidResponse:
            "Strava returned an invalid response."
        case .authorizationDenied(let reason):
            "Strava authorization was denied: \(reason)"
        case .authorizationSessionFailed:
            "Could not start the Strava authorization session."
        case .invalidAuthorizationState:
            "Strava returned an authorization response that did not match this app session."
        case .missingAuthorizationCode:
            "Strava did not return an authorization code."
        case .requestFailed(let statusCode, let message):
            "Strava request failed (\(statusCode)): \(message)"
        }
    }
}

private struct StravaTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

private struct StravaFault: Decodable {
    let message: String
}

private enum StravaEndpoint {
    case authorize
    case oauthToken
    case uploads

    var url: URL {
        switch self {
        case .authorize:
            URL(string: "https://www.strava.com/oauth/mobile/authorize")!
        case .oauthToken:
            URL(string: "https://www.strava.com/oauth/token")!
        case .uploads:
            URL(string: "https://www.strava.com/api/v3/uploads")!
        }
    }
}

private enum StravaOAuth {
    static let callbackScheme = "trainer"
    static let callbackURL = URL(string: "trainer://localhost/strava/oauth")!
}

private final class StravaAuthenticationPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}

private extension Array where Element == URLQueryItem {
    func firstValue(named name: String) -> String? {
        first { $0.name == name }?.value
    }
}

private struct MultipartFormData {
    let boundary = "Boundary-\(UUID().uuidString)"
    private var parts: [Data] = []

    var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    func field(named name: String, value: String) -> MultipartFormData {
        var copy = self
        copy.parts.append(
            """
            --\(boundary)\r
            Content-Disposition: form-data; name="\(name)"\r
            \r
            \(value)\r

            """.multipartData
        )
        return copy
    }

    func file(named name: String, fileURL: URL, mimeType: String) throws -> MultipartFormData {
        var copy = self
        let fileData = try Data(contentsOf: fileURL)
        copy.parts.append(
            """
            --\(boundary)\r
            Content-Disposition: form-data; name="\(name)"; filename="\(fileURL.lastPathComponent)"\r
            Content-Type: \(mimeType)\r
            \r

            """.multipartData
        )
        copy.parts.append(fileData)
        copy.parts.append("\r\n".multipartData)
        return copy
    }

    func encode() -> (data: Data, contentType: String) {
        var data = Data()
        parts.forEach { data.append($0) }
        data.append("--\(boundary)--\r\n".multipartData)
        return (data, contentType)
    }
}

private extension String {
    var multipartData: Data {
        Data(utf8)
    }
}
