import CryptoKit
import Foundation
import Observation

enum SpotifyError: LocalizedError {
    case notSignedIn
    case missingClientID
    case badResponse(Int)
    case rateLimited(retryAfter: Double)
    case authFailed(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Connect your Spotify account first."
        case .missingClientID: "Set SPOTIFY_CLIENT_ID in Config.xcconfig and regenerate the project."
        case .badResponse(let code): "Spotify returned HTTP \(code)."
        case .rateLimited(let s): "Spotify rate limit, retrying in \(Int(s))s."
        case .authFailed(let msg): "Spotify sign-in failed: \(msg)"
        }
    }
}

/// Spotify sign-in using Authorization Code + PKCE (no client secret needed in the app).
@MainActor
@Observable
final class SpotifyAuth {
    static let redirectURI = "lyricdash://callback"
    static let callbackScheme = "lyricdash"
    private static let scopes = "user-read-currently-playing user-read-playback-state"

    private(set) var isSignedIn = false

    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private var expiry: Date = .distantPast
    @ObservationIgnored private var refreshToken: String? {
        didSet { Keychain.set(refreshToken, for: "refreshToken") }
    }
    @ObservationIgnored private var codeVerifier: String?
    @ObservationIgnored private var refreshTask: Task<String, Error>?

    let clientID: String = {
        let id = Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String ?? ""
        return id.contains("paste-your") ? "" : id
    }()

    init() {
        refreshToken = Keychain.get("refreshToken")
        isSignedIn = refreshToken != nil
    }

    // MARK: Sign in

    func makeAuthorizeURL() throws -> URL {
        guard !clientID.isEmpty else { throw SpotifyError.missingClientID }
        let verifier = Self.randomVerifier()
        codeVerifier = verifier
        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "scope", value: Self.scopes),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: Self.challenge(for: verifier)),
        ]
        return c.url!
    }

    func handleCallback(_ url: URL) async throws {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let err = items.first(where: { $0.name == "error" })?.value {
            throw SpotifyError.authFailed(err)
        }
        guard let code = items.first(where: { $0.name == "code" })?.value,
              let verifier = codeVerifier else {
            throw SpotifyError.authFailed("missing code")
        }
        try await requestToken([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ])
        codeVerifier = nil
    }

    func signOut() {
        accessToken = nil
        refreshToken = nil
        expiry = .distantPast
        isSignedIn = false
    }

    // MARK: Tokens

    /// Returns a usable access token, refreshing it if it's about to expire.
    func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh, let accessToken, expiry.timeIntervalSinceNow > 60 {
            return accessToken
        }
        if let refreshTask { return try await refreshTask.value }
        guard let refreshToken else { throw SpotifyError.notSignedIn }

        let task = Task<String, Error> {
            try await self.requestToken([
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": self.clientID,
            ])
            guard let token = self.accessToken else { throw SpotifyError.notSignedIn }
            return token
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Double
        let refresh_token: String?
    }

    private func requestToken(_ form: [String: String]) async throws {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.formEncode(form).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            if status == 400 || status == 401 { signOut() } // refresh token revoked/expired
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SpotifyError.authFailed("HTTP \(status) \(body)")
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = token.access_token
        expiry = Date().addingTimeInterval(token.expires_in)
        if let newRefresh = token.refresh_token { refreshToken = newRefresh }
        isSignedIn = true
    }

    // MARK: PKCE helpers

    private static func randomVerifier() -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<64).map { _ in chars.randomElement()! })
    }

    private static func challenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
    }
}
