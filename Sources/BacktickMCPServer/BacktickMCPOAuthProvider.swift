import CryptoKit
import Foundation

enum BacktickMCPHTTPAuthMode: String, Codable, Equatable {
    case apiKey
    case oauth
}

actor BacktickMCPOAuthProvider {
    private static let primaryScope = "backtick.mcp"
    private static let offlineAccessScope = "offline_access"
    private static let refreshTokenLifetime: TimeInterval = 90 * 24 * 60 * 60 // 90 days

    struct ProtectedResourceMetadata: Codable, Sendable {
        let resource: String
        let authorizationServers: [String]
        let bearerMethodsSupported: [String]
        let scopesSupported: [String]

        enum CodingKeys: String, CodingKey {
            case resource
            case authorizationServers = "authorization_servers"
            case bearerMethodsSupported = "bearer_methods_supported"
            case scopesSupported = "scopes_supported"
        }
    }

    struct AuthorizationServerMetadata: Codable, Sendable {
        let issuer: String
        let authorizationEndpoint: String
        let tokenEndpoint: String
        let registrationEndpoint: String
        let responseTypesSupported: [String]
        let grantTypesSupported: [String]
        let tokenEndpointAuthMethodsSupported: [String]
        let codeChallengeMethodsSupported: [String]
        let scopesSupported: [String]

        enum CodingKeys: String, CodingKey {
            case issuer
            case authorizationEndpoint = "authorization_endpoint"
            case tokenEndpoint = "token_endpoint"
            case registrationEndpoint = "registration_endpoint"
            case responseTypesSupported = "response_types_supported"
            case grantTypesSupported = "grant_types_supported"
            case tokenEndpointAuthMethodsSupported = "token_endpoint_auth_methods_supported"
            case codeChallengeMethodsSupported = "code_challenge_methods_supported"
            case scopesSupported = "scopes_supported"
        }
    }

    struct DynamicClientRegistrationRequest: Codable, Sendable {
        let clientName: String?
        let redirectURIs: [String]
        let tokenEndpointAuthMethod: String?

        enum CodingKeys: String, CodingKey {
            case clientName = "client_name"
            case redirectURIs = "redirect_uris"
            case tokenEndpointAuthMethod = "token_endpoint_auth_method"
        }
    }

    struct DynamicClientRegistration: Codable, Equatable {
        let clientID: String
        let clientName: String?
        let redirectURIs: [String]
        let tokenEndpointAuthMethod: String
        let createdAt: Date
    }

    private struct RefreshGrant: Codable {
        let clientID: String
        let scope: String
        let createdAt: Date
    }

    private struct AccessGrant: Codable {
        let clientID: String
        let scope: String
        let expiresAt: Date
    }

    private struct PersistedState: Codable {
        let dynamicClients: [String: DynamicClientRegistration]
        let refreshTokens: [String: RefreshGrant]
        let accessTokens: [String: AccessGrant]
    }

    struct DynamicClientRegistrationResponse: Codable, Sendable {
        let clientID: String
        let clientIDIssuedAt: Int
        let redirectURIs: [String]
        let grantTypes: [String]
        let responseTypes: [String]
        let tokenEndpointAuthMethod: String
        let clientName: String?

        enum CodingKeys: String, CodingKey {
            case clientID = "client_id"
            case clientIDIssuedAt = "client_id_issued_at"
            case redirectURIs = "redirect_uris"
            case grantTypes = "grant_types"
            case responseTypes = "response_types"
            case tokenEndpointAuthMethod = "token_endpoint_auth_method"
            case clientName = "client_name"
        }
    }

    struct TokenResponse: Codable, Sendable {
        let accessToken: String
        let tokenType: String
        let expiresIn: Int
        let refreshToken: String
        let scope: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case tokenType = "token_type"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
            case scope
        }
    }

    private struct AuthorizationCodeGrant {
        let clientID: String
        let redirectURI: String
        let codeChallenge: String
        let codeChallengeMethod: String
        let scope: String
        let expiresAt: Date
    }

    private let publicBaseURL: URL
    private let fileManager: FileManager
    private let stateFileURL: URL?
    private let accessTokenLifetime: TimeInterval
    private var dynamicClients: [String: DynamicClientRegistration] = [:]
    private var authorizationCodes: [String: AuthorizationCodeGrant] = [:]
    private var refreshTokens: [String: RefreshGrant] = [:]
    private var accessTokens: [String: AccessGrant] = [:]

    init(
        publicBaseURL: URL,
        fileManager: FileManager = .default,
        stateFileURL: URL? = nil,
        accessTokenLifetime: TimeInterval = 3600
    ) {
        self.publicBaseURL = publicBaseURL
        self.fileManager = fileManager
        self.stateFileURL = stateFileURL ?? Self.defaultStateFileURL(fileManager: fileManager)
        self.accessTokenLifetime = max(1, accessTokenLifetime)
        if let persistedState = Self.loadPersistedState(from: self.stateFileURL) {
            let cleanedState = Self.cleanedPersistedState(persistedState)
            dynamicClients = cleanedState.dynamicClients
            refreshTokens = cleanedState.refreshTokens
            accessTokens = cleanedState.accessTokens
        }
        NSLog(
            "BacktickMCPOAuthProvider state loaded: clients=%d refreshTokens=%d accessTokens=%d path=%@",
            dynamicClients.count,
            refreshTokens.count,
            accessTokens.count,
            self.stateFileURL?.path ?? "nil"
        )
    }

    var protectedResourceMetadataURL: URL {
        publicBaseURL.appending(path: ".well-known/oauth-protected-resource")
    }

    var authorizationServerMetadataURL: URL {
        publicBaseURL.appending(path: ".well-known/oauth-authorization-server")
    }

    var openIDConfigurationURL: URL {
        publicBaseURL.appending(path: ".well-known/openid-configuration")
    }

    private var advertisedScopes: [String] {
        [Self.primaryScope, Self.offlineAccessScope]
    }

    func protectedResourceMetadata() -> ProtectedResourceMetadata {
        ProtectedResourceMetadata(
            resource: publicBaseURL.appending(path: "mcp").absoluteString,
            authorizationServers: [publicBaseURL.absoluteString],
            bearerMethodsSupported: ["header"],
            scopesSupported: advertisedScopes
        )
    }

    func authorizationServerMetadata() -> AuthorizationServerMetadata {
        AuthorizationServerMetadata(
            issuer: publicBaseURL.absoluteString,
            authorizationEndpoint: publicBaseURL.appending(path: "oauth/authorize").absoluteString,
            tokenEndpoint: publicBaseURL.appending(path: "oauth/token").absoluteString,
            registrationEndpoint: publicBaseURL.appending(path: "oauth/register").absoluteString,
            responseTypesSupported: ["code"],
            grantTypesSupported: ["authorization_code", "refresh_token"],
            tokenEndpointAuthMethodsSupported: ["none"],
            codeChallengeMethodsSupported: ["S256"],
            scopesSupported: advertisedScopes
        )
    }

    func registerClient(request: DynamicClientRegistrationRequest) throws -> DynamicClientRegistrationResponse {
        guard !request.redirectURIs.isEmpty else {
            throw OAuthError.invalidClientMetadata("redirect_uris is required")
        }

        let tokenEndpointAuthMethod = request.tokenEndpointAuthMethod?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "none"
        guard tokenEndpointAuthMethod == "none" else {
            throw OAuthError.invalidClientMetadata("Only token_endpoint_auth_method=none is supported")
        }

        let sortedRequestURIs = request.redirectURIs.sorted()
        if let existingRegistration = dynamicClients.values.first(where: { existing in
            existing.redirectURIs.sorted() == sortedRequestURIs
                && existing.clientName == request.clientName
                && existing.tokenEndpointAuthMethod == tokenEndpointAuthMethod
        }) {
            return DynamicClientRegistrationResponse(
                clientID: existingRegistration.clientID,
                clientIDIssuedAt: Int(existingRegistration.createdAt.timeIntervalSince1970),
                redirectURIs: existingRegistration.redirectURIs,
                grantTypes: ["authorization_code", "refresh_token"],
                responseTypes: ["code"],
                tokenEndpointAuthMethod: existingRegistration.tokenEndpointAuthMethod,
                clientName: existingRegistration.clientName
            )
        }

        let clientID = Self.randomToken(length: 24)
        let registration = DynamicClientRegistration(
            clientID: clientID,
            clientName: request.clientName,
            redirectURIs: request.redirectURIs,
            tokenEndpointAuthMethod: tokenEndpointAuthMethod,
            createdAt: Date()
        )
        dynamicClients[clientID] = registration
        persistState()

        return DynamicClientRegistrationResponse(
            clientID: registration.clientID,
            clientIDIssuedAt: Int(registration.createdAt.timeIntervalSince1970),
            redirectURIs: registration.redirectURIs,
            grantTypes: ["authorization_code", "refresh_token"],
            responseTypes: ["code"],
            tokenEndpointAuthMethod: registration.tokenEndpointAuthMethod,
            clientName: registration.clientName
        )
    }

    func authorizationPage(parameters: [String: String]) throws -> String {
        let authorizationRequest = try validatedAuthorizationRequest(parameters: parameters)
        let appName = dynamicClients[authorizationRequest.clientID]?.clientName ?? "ChatGPT"

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Authorize Backtick</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #111827; color: #f9fafb; margin: 0; padding: 32px; }
            .card { max-width: 560px; margin: 0 auto; background: #1f2937; border: 1px solid #374151; border-radius: 16px; padding: 24px; }
            h1 { margin: 0 0 12px; font-size: 24px; }
            p { color: #d1d5db; line-height: 1.5; }
            code { background: #111827; padding: 2px 6px; border-radius: 6px; }
            .actions { display: flex; gap: 12px; margin-top: 20px; }
            button { border: 0; border-radius: 10px; padding: 10px 16px; font-weight: 600; cursor: pointer; }
            .approve { background: #10b981; color: #052e16; }
            .deny { background: #374151; color: #f9fafb; }
          </style>
        </head>
        <body>
          <div class="card">
            <h1>Allow \(Self.htmlEscaped(appName)) to use Backtick?</h1>
            <p>This self-hosted Backtick server is asking to connect through OAuth.</p>
            <p><strong>Requested scope:</strong> <code>\(Self.htmlEscaped(authorizationRequest.scope))</code></p>
            <p><strong>Redirect URI:</strong> <code>\(Self.htmlEscaped(authorizationRequest.redirectURI))</code></p>
            <p>Approve only if you started this connection from your own ChatGPT app flow.</p>
            <form method="post" action="/oauth/authorize">
              \(Self.hiddenInput("client_id", authorizationRequest.clientID))
              \(Self.hiddenInput("redirect_uri", authorizationRequest.redirectURI))
              \(Self.hiddenInput("response_type", authorizationRequest.responseType))
              \(Self.hiddenInput("scope", authorizationRequest.scope))
              \(Self.hiddenInput("state", authorizationRequest.state))
              \(Self.hiddenInput("code_challenge", authorizationRequest.codeChallenge))
              \(Self.hiddenInput("code_challenge_method", authorizationRequest.codeChallengeMethod))
              <div class="actions">
                <button class="approve" type="submit" name="decision" value="approve">Approve</button>
                <button class="deny" type="submit" name="decision" value="deny">Deny</button>
              </div>
            </form>
          </div>
        </body>
        </html>
        """
    }

    func completeAuthorization(parameters: [String: String]) throws -> URL {
        let authorizationRequest = try validatedAuthorizationRequest(parameters: parameters)
        let decision = parameters["decision"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard decision == "approve" else {
            return try redirectURL(
                redirectURI: authorizationRequest.redirectURI,
                parameters: [
                    "error": "access_denied",
                    "state": authorizationRequest.state,
                ]
            )
        }

        let code = Self.randomToken(length: 32)
        authorizationCodes[code] = AuthorizationCodeGrant(
            clientID: authorizationRequest.clientID,
            redirectURI: authorizationRequest.redirectURI,
            codeChallenge: authorizationRequest.codeChallenge,
            codeChallengeMethod: authorizationRequest.codeChallengeMethod,
            scope: authorizationRequest.scope,
            expiresAt: Date().addingTimeInterval(300)
        )
        return try redirectURL(
            redirectURI: authorizationRequest.redirectURI,
            parameters: [
                "code": code,
                "state": authorizationRequest.state,
            ]
        )
    }

    func tokenResponse(parameters: [String: String]) throws -> TokenResponse {
        guard let grantType = parameters["grant_type"]?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw OAuthError.invalidGrant("grant_type is required")
        }

        switch grantType {
        case "authorization_code":
            return try authorizationCodeTokenResponse(parameters: parameters)
        case "refresh_token":
            return try refreshTokenResponse(parameters: parameters)
        default:
            throw OAuthError.unsupportedGrantType
        }
    }

    func validateBearerToken(_ token: String) -> Bool {
        cleanupExpiredState()
        guard let grant = accessTokens[token] else {
            return false
        }

        return grant.expiresAt > Date()
    }

    private func authorizationCodeTokenResponse(parameters: [String: String]) throws -> TokenResponse {
        cleanupExpiredState()

        guard let code = parameters["code"],
              let clientID = parameters["client_id"],
              let redirectURI = parameters["redirect_uri"],
              let codeVerifier = parameters["code_verifier"] else {
            throw OAuthError.invalidGrant("code, client_id, redirect_uri, and code_verifier are required")
        }

        guard let registration = dynamicClients[clientID] else {
            logTokenExchangeRejection(
                errorCode: "invalid_client",
                flow: "authorization_code",
                clientID: clientID,
                redirectURI: redirectURI,
                authorizationCode: code,
                registrationPresent: false,
                authorizationCodePresent: authorizationCodes[code] != nil
            )
            throw OAuthError.invalidClient
        }

        guard registration.redirectURIs.contains(redirectURI) else {
            throw OAuthError.invalidGrant("redirect_uri does not match registered redirect_uris")
        }

        guard let grant = authorizationCodes.removeValue(forKey: code) else {
            throw OAuthError.invalidGrant("authorization code is invalid or already used")
        }

        guard grant.clientID == clientID else {
            throw OAuthError.invalidGrant("client_id does not match authorization code")
        }

        guard grant.redirectURI == redirectURI else {
            throw OAuthError.invalidGrant("redirect_uri does not match authorization code")
        }

        guard grant.expiresAt > Date() else {
            throw OAuthError.invalidGrant("authorization code has expired")
        }

        guard grant.codeChallengeMethod.uppercased() == "S256" else {
            throw OAuthError.invalidGrant("Only S256 PKCE is supported")
        }

        let computedChallenge = Self.base64URLEncode(Data(SHA256.hash(data: Data(codeVerifier.utf8))))
        guard computedChallenge == grant.codeChallenge else {
            throw OAuthError.invalidGrant("code_verifier does not match code_challenge")
        }

        let accessToken = Self.randomToken(length: 48)
        let refreshToken = Self.randomToken(length: 48)
        let accessGrant = AccessGrant(
            clientID: clientID,
            scope: grant.scope,
            expiresAt: Date().addingTimeInterval(accessTokenLifetime)
        )
        accessTokens[accessToken] = accessGrant
        refreshTokens[refreshToken] = RefreshGrant(
            clientID: clientID,
            scope: grant.scope,
            createdAt: Date()
        )
        persistState()

        return TokenResponse(
            accessToken: accessToken,
            tokenType: "Bearer",
            expiresIn: max(1, Int(accessTokenLifetime.rounded())),
            refreshToken: refreshToken,
            scope: grant.scope
        )
    }

    private func refreshTokenResponse(parameters: [String: String]) throws -> TokenResponse {
        cleanupExpiredState()

        guard let refreshToken = parameters["refresh_token"],
              let clientID = parameters["client_id"] else {
            throw OAuthError.invalidGrant("refresh_token and client_id are required")
        }

        let knownRefreshGrant = refreshTokens[refreshToken]

        guard dynamicClients[clientID] != nil else {
            logTokenExchangeRejection(
                errorCode: "invalid_client",
                flow: "refresh_token",
                clientID: clientID,
                refreshToken: refreshToken,
                registrationPresent: false,
                refreshTokenPresent: knownRefreshGrant != nil,
                refreshClientMatches: knownRefreshGrant?.clientID == clientID
            )
            throw OAuthError.invalidClient
        }

        guard let refreshGrant = knownRefreshGrant,
              refreshGrant.clientID == clientID else {
            logTokenExchangeRejection(
                errorCode: "invalid_grant",
                flow: "refresh_token",
                clientID: clientID,
                refreshToken: refreshToken,
                registrationPresent: true,
                refreshTokenPresent: knownRefreshGrant != nil,
                refreshClientMatches: knownRefreshGrant?.clientID == clientID
            )
            throw OAuthError.invalidGrant("refresh token is invalid")
        }

        let refreshTokenExpiry = refreshGrant.createdAt.addingTimeInterval(Self.refreshTokenLifetime)
        guard refreshTokenExpiry > Date() else {
            refreshTokens.removeValue(forKey: refreshToken)
            persistState()
            throw OAuthError.invalidGrant("refresh token has expired")
        }

        let accessToken = Self.randomToken(length: 48)
        accessTokens[accessToken] = AccessGrant(
            clientID: clientID,
            scope: refreshGrant.scope,
            expiresAt: Date().addingTimeInterval(accessTokenLifetime)
        )
        persistState()

        return TokenResponse(
            accessToken: accessToken,
            tokenType: "Bearer",
            expiresIn: max(1, Int(accessTokenLifetime.rounded())),
            refreshToken: refreshToken,
            scope: refreshGrant.scope
        )
    }

    private func validatedAuthorizationRequest(parameters: [String: String]) throws -> AuthorizationRequest {
        guard let clientID = parameters["client_id"],
              let redirectURI = parameters["redirect_uri"],
              let responseType = parameters["response_type"],
              let state = parameters["state"],
              let codeChallenge = parameters["code_challenge"],
              let codeChallengeMethod = parameters["code_challenge_method"] else {
            throw OAuthError.invalidAuthorizeRequest("Missing one or more required OAuth parameters")
        }

        guard responseType == "code" else {
            throw OAuthError.invalidAuthorizeRequest("Only response_type=code is supported")
        }

        guard codeChallengeMethod.uppercased() == "S256" else {
            throw OAuthError.invalidAuthorizeRequest("Only S256 PKCE is supported")
        }

        guard let registration = dynamicClients[clientID] else {
            throw OAuthError.invalidClient
        }

        guard registration.redirectURIs.contains(redirectURI) else {
            throw OAuthError.invalidAuthorizeRequest("redirect_uri is not registered")
        }

        let scope = parameters["scope"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedScope = scope?.isEmpty == false ? scope! : Self.primaryScope
        return AuthorizationRequest(
            clientID: clientID,
            redirectURI: redirectURI,
            responseType: responseType,
            scope: normalizedScope,
            state: state,
            codeChallenge: codeChallenge,
            codeChallengeMethod: codeChallengeMethod
        )
    }

    private func redirectURL(redirectURI: String, parameters: [String: String]) throws -> URL {
        guard var components = URLComponents(string: redirectURI) else {
            throw OAuthError.invalidRedirectURI
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(contentsOf: parameters.map(URLQueryItem.init))
        components.queryItems = queryItems

        guard let url = components.url else {
            throw OAuthError.invalidRedirectURI
        }

        return url
    }

    private func cleanupExpiredState() {
        let now = Date()
        let previousAuthorizationCodeCount = authorizationCodes.count
        let previousAccessTokenCount = accessTokens.count
        let previousRefreshTokenCount = refreshTokens.count
        authorizationCodes = authorizationCodes.filter { $0.value.expiresAt > now }
        accessTokens = accessTokens.filter { $0.value.expiresAt > now }
        let refreshTokenExpiry = now.addingTimeInterval(-Self.refreshTokenLifetime)
        refreshTokens = refreshTokens.filter { $0.value.createdAt > refreshTokenExpiry }
        if authorizationCodes.count != previousAuthorizationCodeCount
            || accessTokens.count != previousAccessTokenCount
            || refreshTokens.count != previousRefreshTokenCount
        {
            persistState()
        }
    }

    private func logTokenExchangeRejection(
        errorCode: String,
        flow: String,
        clientID: String?,
        redirectURI: String? = nil,
        authorizationCode: String? = nil,
        refreshToken: String? = nil,
        registrationPresent: Bool? = nil,
        authorizationCodePresent: Bool? = nil,
        refreshTokenPresent: Bool? = nil,
        refreshClientMatches: Bool? = nil
    ) {
        var fields = ["flow=\(flow)"]

        if let clientID, !clientID.isEmpty {
            fields.append("clientID=\(Self.redactedToken(clientID))")
        }
        if let registrationPresent {
            fields.append("clientRegistered=\(Self.logBool(registrationPresent))")
        }
        if let redirectHost = Self.redirectHost(from: redirectURI) {
            fields.append("redirectHost=\(redirectHost)")
        }
        if let redirectPathHash = Self.redirectPathHash(from: redirectURI) {
            fields.append("redirectPathHash=\(redirectPathHash)")
        }
        if let authorizationCode, !authorizationCode.isEmpty {
            fields.append("authorizationCode=\(Self.redactedToken(authorizationCode))")
        }
        if let authorizationCodePresent {
            fields.append("authorizationCodePresent=\(Self.logBool(authorizationCodePresent))")
        }
        if let refreshToken, !refreshToken.isEmpty {
            fields.append("refreshToken=\(Self.redactedToken(refreshToken))")
        }
        if let refreshTokenPresent {
            fields.append("refreshTokenPresent=\(Self.logBool(refreshTokenPresent))")
        }
        if let refreshClientMatches {
            fields.append("refreshClientMatches=\(Self.logBool(refreshClientMatches))")
        }

        fields.append("knownClients=\(dynamicClients.count)")
        fields.append("storedRefreshTokens=\(refreshTokens.count)")
        fields.append("activeAccessTokens=\(accessTokens.count)")

        NSLog(
            "BacktickMCPOAuthProvider token exchange rejected: %@ %@",
            errorCode,
            fields.joined(separator: " ")
        )
    }

    private func persistState() {
        guard let stateFileURL else {
            return
        }

        let persistedState = PersistedState(
            dynamicClients: dynamicClients,
            refreshTokens: refreshTokens,
            accessTokens: accessTokens
        )

        do {
            let directoryURL = stateFileURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(persistedState)
            try data.write(to: stateFileURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: stateFileURL.path
            )
        } catch {
            NSLog("BacktickMCPOAuthProvider persist failed: %@", error.localizedDescription)
        }
    }

    private static func defaultStateFileURL(fileManager: FileManager) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("PromptCue", isDirectory: true)
            .appendingPathComponent("BacktickMCPOAuthState.json", isDirectory: false)
    }

    private static func loadPersistedState(from stateFileURL: URL?) -> PersistedState? {
        guard let stateFileURL,
              let data = try? Data(contentsOf: stateFileURL) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(PersistedState.self, from: data)
        } catch {
            NSLog("BacktickMCPOAuthProvider load failed: %@", error.localizedDescription)
            return nil
        }
    }

    private static func cleanedPersistedState(_ persistedState: PersistedState) -> PersistedState {
        let now = Date()
        let refreshTokenExpiry = now.addingTimeInterval(-refreshTokenLifetime)
        return PersistedState(
            dynamicClients: persistedState.dynamicClients,
            refreshTokens: persistedState.refreshTokens.filter { $0.value.createdAt > refreshTokenExpiry },
            accessTokens: persistedState.accessTokens.filter { $0.value.expiresAt > now }
        )
    }

    private static func redactedToken(_ value: String) -> String {
        let prefix = value.prefix(6)
        return "\(prefix)…"
    }

    private static func redirectHost(from redirectURI: String?) -> String? {
        guard let redirectURI,
              let components = URLComponents(string: redirectURI),
              let host = components.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }

        return host
    }

    private static func redirectPathHash(from redirectURI: String?) -> String? {
        guard let redirectURI,
              let components = URLComponents(string: redirectURI) else {
            return nil
        }

        let path = components.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, path != "/" else {
            return nil
        }

        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    private static func logBool(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    private struct AuthorizationRequest {
        let clientID: String
        let redirectURI: String
        let responseType: String
        let scope: String
        let state: String
        let codeChallenge: String
        let codeChallengeMethod: String
    }

    enum OAuthError: LocalizedError {
        case invalidClientMetadata(String)
        case invalidClient
        case invalidAuthorizeRequest(String)
        case invalidGrant(String)
        case invalidRedirectURI
        case unsupportedGrantType

        var errorDescription: String? {
            switch self {
            case .invalidClientMetadata(let detail):
                return detail
            case .invalidClient:
                return "invalid_client"
            case .invalidAuthorizeRequest(let detail):
                return detail
            case .invalidGrant(let detail):
                return detail
            case .invalidRedirectURI:
                return "redirect_uri is invalid"
            case .unsupportedGrantType:
                return "unsupported_grant_type"
            }
        }

        var oauthErrorCode: String {
            switch self {
            case .invalidClientMetadata:
                return "invalid_client_metadata"
            case .invalidClient:
                return "invalid_client"
            case .invalidAuthorizeRequest:
                return "invalid_request"
            case .invalidGrant:
                return "invalid_grant"
            case .invalidRedirectURI:
                return "invalid_request"
            case .unsupportedGrantType:
                return "unsupported_grant_type"
            }
        }
    }

    private static func randomToken(length: Int) -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        guard status == errSecSuccess else {
            return String((0..<length).map { _ in characters.randomElement()! })
        }
        return String(bytes.map { characters[Int($0) % characters.count] })
    }

    private static func base64URLEncode<D: DataProtocol>(_ data: D) -> String {
        Data(data).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func hiddenInput(_ name: String, _ value: String) -> String {
        #"<input type="hidden" name="\#(htmlEscaped(name))" value="\#(htmlEscaped(value))">"#
    }

    private static func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
