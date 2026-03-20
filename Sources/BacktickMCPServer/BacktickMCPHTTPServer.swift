import Foundation
import Network

struct BacktickMCPHTTPConfiguration {
    var host: String = "127.0.0.1"
    var port: UInt16 = 8321
    var authMode: BacktickMCPHTTPAuthMode = .apiKey
    var apiKey: String?
    var publicBaseURL: URL?
    var oauthStateFileURL: URL?
    var accessTokenLifetime: TimeInterval = 3600
}

struct BacktickMCPHTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}

struct BacktickMCPHTTPResponse {
    let statusCode: Int
    let reasonPhrase: String
    let headers: [String: String]
    let body: Data

    func serialized() -> Data {
        let connectionValue = headers["Connection"] ?? "close"
        var lines = [
            "HTTP/1.1 \(statusCode) \(reasonPhrase)",
            "Content-Length: \(body.count)",
            "Connection: \(connectionValue)",
        ]
        for (name, value) in headers.sorted(by: { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }) {
            if name.lowercased() == "connection" { continue }
            lines.append("\(name): \(value)")
        }
        lines.append("")
        lines.append("")

        var data = Data(lines.joined(separator: "\r\n").utf8)
        data.append(body)
        return data
    }
}

enum BacktickMCPHTTPRequestParseResult {
    case incomplete
    case failure(String)
    case success(BacktickMCPHTTPRequest)
}

enum BacktickMCPHTTPRequestParser {
    private static let headerDelimiter = Data([13, 10, 13, 10])

    static func parse(_ data: Data) -> BacktickMCPHTTPRequestParseResult {
        guard let headerRange = data.range(of: headerDelimiter) else {
            return .incomplete
        }

        let headerData = data.subdata(in: data.startIndex..<headerRange.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return .failure("Request headers were not valid UTF-8.")
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            return .failure("Missing HTTP request line.")
        }

        let requestLineParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestLineParts.count == 3 else {
            return .failure("Malformed HTTP request line.")
        }

        let method = String(requestLineParts[0]).uppercased()
        let path = String(requestLineParts[1])
        guard String(requestLineParts[2]).hasPrefix("HTTP/1.") else {
            return .failure("Only HTTP/1.x is supported.")
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let separator = line.firstIndex(of: ":") else {
                return .failure("Malformed HTTP header.")
            }

            let name = line[..<separator]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
        }

        let contentLength = Int(headers["content-length"] ?? "") ?? 0
        let bodyStartIndex = headerRange.upperBound
        let bodyLength = data.distance(from: bodyStartIndex, to: data.endIndex)
        guard bodyLength >= contentLength else {
            return .incomplete
        }

        let bodyEndIndex = data.index(bodyStartIndex, offsetBy: contentLength)
        let body = data.subdata(in: bodyStartIndex..<bodyEndIndex)
        return .success(
            BacktickMCPHTTPRequest(
                method: method,
                path: path,
                headers: headers,
                body: body
            )
        )
    }
}

final class BacktickMCPHTTPHandler {
    private enum RemoteClientSurface: String {
        case web
        case macos
        case iphone
        case ipad
        case android
        case unknown
    }

    private struct ProtectedRequestLogSummary {
        let rpcMethod: String?
        let targetKind: String?
        let targetName: String?
    }

    private let session: BacktickMCPServerSession
    private let configuration: BacktickMCPHTTPConfiguration
    private let apiKey: String?
    private let oauthProvider: BacktickMCPOAuthProvider?
    private let logger: (String) -> Void

    init(
        session: BacktickMCPServerSession,
        configuration: BacktickMCPHTTPConfiguration,
        logger: @escaping (String) -> Void = { _ in }
    ) {
        self.session = session
        self.configuration = configuration
        self.apiKey = configuration.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.logger = logger
        if configuration.authMode == .oauth, let publicBaseURL = configuration.publicBaseURL {
            self.oauthProvider = BacktickMCPOAuthProvider(
                publicBaseURL: publicBaseURL,
                stateFileURL: configuration.oauthStateFileURL,
                accessTokenLifetime: configuration.accessTokenLifetime
            )
        } else {
            self.oauthProvider = nil
        }
    }

    func response(for request: BacktickMCPHTTPRequest) async -> BacktickMCPHTTPResponse {
        switch request.method {
        case "GET":
            return await responseForGet(request)
        case "POST":
            return await responseForPost(request)
        case "OPTIONS":
            return BacktickMCPHTTPResponse(
                statusCode: 204,
                reasonPhrase: "No Content",
                headers: corsHeaders(),
                body: Data()
            )
        default:
            return textResponse(
                statusCode: 405,
                reasonPhrase: "Method Not Allowed",
                body: "Only GET, POST, and OPTIONS are supported."
            )
        }
    }

    private func responseForGet(_ request: BacktickMCPHTTPRequest) async -> BacktickMCPHTTPResponse {
        let components = requestURLComponents(for: request)

        switch components.path {
        case "/health":
            return jsonResponse(
                statusCode: 200,
                reasonPhrase: "OK",
                body: Data(#"{"status":"ok"}"#.utf8)
            )
        case "/.well-known/oauth-protected-resource",
             "/mcp/.well-known/oauth-protected-resource",
             "/.well-known/oauth-protected-resource/mcp":
            guard let oauthProvider else {
                return textResponse(
                    statusCode: 404,
                    reasonPhrase: "Not Found",
                    body: "OAuth is not enabled."
                )
            }
            return jsonObjectResponse(
                statusCode: 200,
                reasonPhrase: "OK",
                object: await oauthProvider.protectedResourceMetadata()
            )
        case "/.well-known/oauth-authorization-server",
             "/.well-known/oauth-authorization-server/mcp":
            guard let oauthProvider else {
                return textResponse(
                    statusCode: 404,
                    reasonPhrase: "Not Found",
                    body: "OAuth is not enabled."
                )
            }
            return jsonObjectResponse(
                statusCode: 200,
                reasonPhrase: "OK",
                object: await oauthProvider.authorizationServerMetadata()
            )
        case "/.well-known/openid-configuration",
             "/.well-known/openid-configuration/mcp":
            guard let oauthProvider else {
                return textResponse(
                    statusCode: 404,
                    reasonPhrase: "Not Found",
                    body: "OAuth is not enabled."
                )
            }
            return jsonObjectResponse(
                statusCode: 200,
                reasonPhrase: "OK",
                object: await oauthProvider.authorizationServerMetadata()
            )
        case "/oauth/authorize":
            guard let oauthProvider else {
                return textResponse(
                    statusCode: 404,
                    reasonPhrase: "Not Found",
                    body: "OAuth is not enabled."
                )
            }
            do {
                let page = try await oauthProvider.authorizationPage(parameters: queryParameters(from: components))
                return htmlResponse(
                    statusCode: 200,
                    reasonPhrase: "OK",
                    body: page
                )
            } catch let error as BacktickMCPOAuthProvider.OAuthError {
                return oauthErrorResponse(statusCode: 400, error: error)
            } catch {
                return textResponse(
                    statusCode: 400,
                    reasonPhrase: "Bad Request",
                    body: error.localizedDescription
                )
            }
        case "/", "/mcp":
            return jsonResponse(
                statusCode: 200,
                reasonPhrase: "OK",
                body: Data(#"{"name":"backtick-stack-mcp","transport":"streamable-http-foundation","ready":true}"#.utf8)
            )
        default:
            return textResponse(
                statusCode: 404,
                reasonPhrase: "Not Found",
                body: "Unknown path."
            )
        }
    }

    private func responseForPost(_ request: BacktickMCPHTTPRequest) async -> BacktickMCPHTTPResponse {
        let components = requestURLComponents(for: request)

        switch components.path {
        case "/oauth/register":
            return await oauthRegistrationResponse(for: request)
        case "/oauth/authorize":
            return await oauthAuthorizeResponse(for: request)
        case "/oauth/token":
            return await oauthTokenResponse(for: request)
        case "/", "/mcp":
            break
        default:
            return textResponse(
                statusCode: 404,
                reasonPhrase: "Not Found",
                body: "Unknown path."
            )
        }

        guard !request.body.isEmpty else {
            return BacktickMCPHTTPResponse(
                statusCode: 200,
                reasonPhrase: "OK",
                headers: corsHeaders(),
                body: Data()
            )
        }

        guard await isAuthorized(headers: request.headers) else {
            return unauthorizedResponse()
        }

        guard let responseData = await session.handleRequestData(request.body) else {
            var notificationHeaders = corsHeaders()
            if let sessionID = await session.sessionID {
                notificationHeaders["Mcp-Session-Id"] = sessionID
            }
            return BacktickMCPHTTPResponse(
                statusCode: 202,
                reasonPhrase: "Accepted",
                headers: notificationHeaders,
                body: Data()
            )
        }

        if configuration.authMode == .oauth {
            logProtectedRemoteRequest(request)
        }

        var extraHeaders = [
            "Cache-Control": "no-store",
        ]
        if let sessionID = await session.sessionID {
            extraHeaders["Mcp-Session-Id"] = sessionID
        }

        return jsonResponse(
            statusCode: 200,
            reasonPhrase: "OK",
            body: responseData,
            extraHeaders: extraHeaders
        )
    }

    private func oauthRegistrationResponse(for request: BacktickMCPHTTPRequest) async -> BacktickMCPHTTPResponse {
        guard let oauthProvider else {
            return textResponse(
                statusCode: 404,
                reasonPhrase: "Not Found",
                body: "OAuth is not enabled."
            )
        }

        do {
            let registrationRequest = try JSONDecoder().decode(
                BacktickMCPOAuthProvider.DynamicClientRegistrationRequest.self,
                from: request.body
            )
            let responseObject = try await oauthProvider.registerClient(request: registrationRequest)
            return jsonObjectResponse(
                statusCode: 201,
                reasonPhrase: "Created",
                object: responseObject
            )
        } catch let error as BacktickMCPOAuthProvider.OAuthError {
            return oauthErrorResponse(statusCode: 400, error: error)
        } catch {
            return textResponse(
                statusCode: 400,
                reasonPhrase: "Bad Request",
                body: error.localizedDescription
            )
        }
    }

    private func oauthAuthorizeResponse(for request: BacktickMCPHTTPRequest) async -> BacktickMCPHTTPResponse {
        guard let oauthProvider else {
            return textResponse(
                statusCode: 404,
                reasonPhrase: "Not Found",
                body: "OAuth is not enabled."
            )
        }

        do {
            let redirectURL = try await oauthProvider.completeAuthorization(
                parameters: formParameters(from: request.body)
            )
            return BacktickMCPHTTPResponse(
                statusCode: 302,
                reasonPhrase: "Found",
                headers: [
                    "Location": redirectURL.absoluteString,
                ].merging(corsHeaders(), uniquingKeysWith: { _, new in new }),
                body: Data()
            )
        } catch let error as BacktickMCPOAuthProvider.OAuthError {
            return oauthErrorResponse(statusCode: 400, error: error)
        } catch {
            return textResponse(
                statusCode: 400,
                reasonPhrase: "Bad Request",
                body: error.localizedDescription
            )
        }
    }

    private func oauthTokenResponse(for request: BacktickMCPHTTPRequest) async -> BacktickMCPHTTPResponse {
        guard let oauthProvider else {
            return textResponse(
                statusCode: 404,
                reasonPhrase: "Not Found",
                body: "OAuth is not enabled."
            )
        }

        let parameters = formParameters(from: request.body)

        do {
            let responseObject = try await oauthProvider.tokenResponse(
                parameters: parameters
            )
            return jsonObjectResponse(
                statusCode: 200,
                reasonPhrase: "OK",
                object: responseObject,
                extraHeaders: [
                    "Cache-Control": "no-store",
                ]
            )
        } catch let error as BacktickMCPOAuthProvider.OAuthError {
            logOAuthTokenRejection(error, request: request, parameters: parameters)
            return oauthErrorResponse(statusCode: 400, error: error)
        } catch {
            return textResponse(
                statusCode: 400,
                reasonPhrase: "Bad Request",
                body: error.localizedDescription
            )
        }
    }

    private func isAuthorized(headers: [String: String]) async -> Bool {
        switch configuration.authMode {
        case .apiKey:
            guard let expectedKey = apiKey, !expectedKey.isEmpty else {
                return true
            }

            let providedKey = headers["x-api-key"]
                ?? authorizationToken(from: headers["authorization"])
            return providedKey == expectedKey
        case .oauth:
            guard let oauthProvider,
                  let token = authorizationToken(from: headers["authorization"]) else {
                return false
            }
            return await oauthProvider.validateBearerToken(token)
        }
    }

    private func authorizationToken(from header: String?) -> String? {
        guard let header else {
            return nil
        }

        let prefix = "bearer "
        guard header.lowercased().hasPrefix(prefix) else {
            return nil
        }

        return String(header.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func requestURLComponents(for request: BacktickMCPHTTPRequest) -> URLComponents {
        URLComponents(string: "http://\(configuration.host)\(request.path)") ?? URLComponents()
    }

    private func queryParameters(from components: URLComponents) -> [String: String] {
        (components.queryItems ?? []).reduce(into: [String: String]()) { result, item in
            result[item.name] = item.value ?? ""
        }
    }

    private func formParameters(from data: Data) -> [String: String] {
        guard let body = String(data: data, encoding: .utf8), !body.isEmpty else {
            return [:]
        }

        return body
            .split(separator: "&")
            .reduce(into: [String: String]()) { result, pair in
                let pieces = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let rawKey = pieces.first else {
                    return
                }

                let rawValue = pieces.count > 1 ? String(pieces[1]) : ""
                let key = Self.urlDecode(String(rawKey))
                result[key] = Self.urlDecode(rawValue)
            }
    }

    private func unauthorizedResponse() -> BacktickMCPHTTPResponse {
        var headers: [String: String] = [
            "Content-Type": "application/json",
        ]

        switch configuration.authMode {
        case .apiKey:
            headers["WWW-Authenticate"] = "Bearer"
            return BacktickMCPHTTPResponse(
                statusCode: 401,
                reasonPhrase: "Unauthorized",
                headers: headers.merging(corsHeaders(), uniquingKeysWith: { _, new in new }),
                body: Data(#"{"error":"Missing or invalid API key"}"#.utf8)
            )
        case .oauth:
            if let publicBaseURL = configuration.publicBaseURL {
                headers["WWW-Authenticate"] = "Bearer resource_metadata=\"\(publicBaseURL.appending(path: ".well-known/oauth-protected-resource/mcp").absoluteString)\""
            } else {
                headers["WWW-Authenticate"] = "Bearer"
            }
            return BacktickMCPHTTPResponse(
                statusCode: 401,
                reasonPhrase: "Unauthorized",
                headers: headers.merging(corsHeaders(), uniquingKeysWith: { _, new in new }),
                body: Data(#"{"error":"Missing or invalid OAuth access token"}"#.utf8)
            )
        }
    }

    private func logProtectedRemoteRequest(_ request: BacktickMCPHTTPRequest) {
        let summary = protectedRequestSummary(from: request.body)
        var fields = [
            "surface=\(remoteClientSurface(from: request.headers).rawValue)",
            "path=\(requestURLComponents(for: request).path)",
            "bodyBytes=\(request.body.count)"
        ]

        if let rpcMethod = summary.rpcMethod, !rpcMethod.isEmpty {
            fields.append("rpcMethod=\(Self.logValue(rpcMethod))")
        }
        if let targetKind = summary.targetKind, !targetKind.isEmpty {
            fields.append("targetKind=\(Self.logValue(targetKind))")
        }
        if let targetName = summary.targetName, !targetName.isEmpty {
            fields.append("targetName=\(Self.logValue(targetName))")
        }

        logger("Backtick MCP HTTP served protected remote request \(fields.joined(separator: " "))")
    }

    private func logOAuthTokenRejection(
        _ error: BacktickMCPOAuthProvider.OAuthError,
        request: BacktickMCPHTTPRequest,
        parameters: [String: String]
    ) {
        let errorCode = error.oauthErrorCode
        guard errorCode == "invalid_client" || errorCode == "invalid_grant" else {
            return
        }

        var fields = [
            "error=\(errorCode)",
            "surface=\(remoteClientSurface(from: request.headers).rawValue)",
            "path=\(requestURLComponents(for: request).path)"
        ]

        if let grantType = parameters["grant_type"], !grantType.isEmpty {
            fields.append("grantType=\(Self.logValue(grantType))")
        }
        if let clientID = parameters["client_id"], !clientID.isEmpty {
            fields.append("clientID=\(Self.redactedToken(clientID))")
        }

        logger("Backtick MCP HTTP OAuth token request rejected \(fields.joined(separator: " "))")
    }

    private func protectedRequestSummary(from body: Data) -> ProtectedRequestLogSummary {
        let object: Any
        guard let parsedObject = try? JSONSerialization.jsonObject(with: body) else {
            return ProtectedRequestLogSummary(
                rpcMethod: nil,
                targetKind: nil,
                targetName: nil
            )
        }
        object = parsedObject

        let requestObject: [String: Any]?
        if let dictionary = object as? [String: Any] {
            requestObject = dictionary
        } else if let array = object as? [Any],
                  let firstObject = array.first as? [String: Any] {
            requestObject = firstObject
        } else {
            requestObject = nil
        }

        guard let requestObject else {
            return ProtectedRequestLogSummary(
                rpcMethod: nil,
                targetKind: nil,
                targetName: nil
            )
        }

        let rpcMethod = requestObject["method"] as? String
        let parameters = requestObject["params"] as? [String: Any]
        let targetKind: String?
        let targetName: String?

        switch rpcMethod {
        case "tools/call":
            targetKind = "tool"
            targetName = parameters?["name"] as? String
        case "prompts/get":
            targetKind = "prompt"
            targetName = parameters?["name"] as? String
        case "resources/read":
            targetKind = "resource"
            targetName = parameters?["uri"] as? String
        default:
            targetKind = nil
            targetName = nil
        }

        return ProtectedRequestLogSummary(
            rpcMethod: rpcMethod,
            targetKind: targetKind,
            targetName: targetName
        )
    }

    private func remoteClientSurface(from headers: [String: String]) -> RemoteClientSurface {
        let userAgent = headers["user-agent"]?.lowercased() ?? ""
        if userAgent.contains("iphone") || userAgent.contains("ios") {
            return .iphone
        }
        if userAgent.contains("ipad") {
            return .ipad
        }
        if userAgent.contains("android") {
            return .android
        }
        if userAgent.contains("macintosh") || userAgent.contains("mac os x") {
            return .macos
        }
        let isBrowserLike = userAgent.contains("mozilla/")
            || userAgent.contains("chrome/")
            || userAgent.contains("safari/")
            || userAgent.contains("firefox/")
            || userAgent.contains("edg/")
        if isBrowserLike {
            return .web
        }

        return .unknown
    }

    private static func redactedToken(_ value: String) -> String {
        let prefix = value.prefix(6)
        return "\(prefix)…"
    }

    private static func logValue(_ value: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return "-"
        }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~/"))
        let sanitizedScalars = trimmedValue.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(String(scalar)) : "_"
        }
        return String(sanitizedScalars)
    }

    private func jsonResponse(
        statusCode: Int,
        reasonPhrase: String,
        body: Data,
        extraHeaders: [String: String] = [:]
    ) -> BacktickMCPHTTPResponse {
        BacktickMCPHTTPResponse(
            statusCode: statusCode,
            reasonPhrase: reasonPhrase,
            headers: [
                "Content-Type": "application/json",
            ].merging(corsHeaders(), uniquingKeysWith: { _, new in new })
                .merging(extraHeaders, uniquingKeysWith: { _, new in new }),
            body: body
        )
    }

    private func jsonObjectResponse<T: Encodable>(
        statusCode: Int,
        reasonPhrase: String,
        object: T,
        extraHeaders: [String: String] = [:]
    ) -> BacktickMCPHTTPResponse {
        let encoder = JSONEncoder()
        if #available(macOS 13.0, *) {
            encoder.outputFormatting = [.sortedKeys]
        }
        let body = (try? encoder.encode(object)) ?? Data("{}".utf8)
        return jsonResponse(
            statusCode: statusCode,
            reasonPhrase: reasonPhrase,
            body: body,
            extraHeaders: extraHeaders
        )
    }

    private func textResponse(
        statusCode: Int,
        reasonPhrase: String,
        body: String
    ) -> BacktickMCPHTTPResponse {
        BacktickMCPHTTPResponse(
            statusCode: statusCode,
            reasonPhrase: reasonPhrase,
            headers: [
                "Content-Type": "text/plain; charset=utf-8",
            ].merging(corsHeaders(), uniquingKeysWith: { _, new in new }),
            body: Data(body.utf8)
        )
    }

    private func htmlResponse(
        statusCode: Int,
        reasonPhrase: String,
        body: String
    ) -> BacktickMCPHTTPResponse {
        BacktickMCPHTTPResponse(
            statusCode: statusCode,
            reasonPhrase: reasonPhrase,
            headers: [
                "Content-Type": "text/html; charset=utf-8",
            ].merging(corsHeaders(), uniquingKeysWith: { _, new in new }),
            body: Data(body.utf8)
        )
    }

    private func oauthErrorResponse(
        statusCode: Int,
        error: BacktickMCPOAuthProvider.OAuthError
    ) -> BacktickMCPHTTPResponse {
        jsonObjectResponse(
            statusCode: statusCode,
            reasonPhrase: "Bad Request",
            object: [
                "error": error.oauthErrorCode,
                "error_description": error.localizedDescription,
            ]
        )
    }

    private func corsHeaders() -> [String: String] {
        [
            "Access-Control-Allow-Headers": "Authorization, Content-Type, X-API-Key",
            "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
            "Access-Control-Allow-Origin": "*",
        ]
    }

    private static func urlDecode(_ value: String) -> String {
        value
            .replacingOccurrences(of: "+", with: " ")
            .removingPercentEncoding ?? value
    }
}

final class BacktickMCPHTTPServer: @unchecked Sendable {
    private final class ConnectionState: @unchecked Sendable {
        var buffer = Data()
        var timeoutTask: Task<Void, Never>?

        func scheduleTimeout(seconds: UInt64, onTimeout: @escaping @Sendable () -> Void) {
            timeoutTask?.cancel()
            timeoutTask = Task {
                do {
                    try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                    onTimeout()
                } catch {
                    // Task was cancelled — no timeout action needed
                }
            }
        }

        func cancelTimeout() {
            timeoutTask?.cancel()
            timeoutTask = nil
        }
    }

    private let configuration: BacktickMCPHTTPConfiguration
    private let handler: BacktickMCPHTTPHandler
    private let logger: (String) -> Void
    private let queue = DispatchQueue(label: "BacktickMCP.HTTPServer")
    private let listener: NWListener
    private let stateLock = NSLock()
    private var didResumeReadyContinuation = false
    private var isStopped = false

    init(
        configuration: BacktickMCPHTTPConfiguration,
        session: BacktickMCPServerSession,
        logger: @escaping (String) -> Void
    ) throws {
        self.configuration = configuration
        self.logger = logger
        self.handler = BacktickMCPHTTPHandler(
            session: session,
            configuration: configuration,
            logger: logger
        )
        self.listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: configuration.port)!)
    }

    func run() async throws {
        setStopped(false)

        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }

                switch state {
                case .ready:
                    guard !self.didResumeReadyContinuation else { return }
                    self.didResumeReadyContinuation = true
                    let port = self.listener.port?.rawValue ?? self.configuration.port
                    self.logger("Backtick MCP HTTP listening on http://\(self.configuration.host):\(port)/mcp")
                    continuation.resume()
                case .failed(let error):
                    self.setStopped(true)
                    guard !self.didResumeReadyContinuation else { return }
                    self.didResumeReadyContinuation = true
                    continuation.resume(throwing: error)
                case .cancelled:
                    self.setStopped(true)
                    guard !self.didResumeReadyContinuation else { return }
                    self.didResumeReadyContinuation = true
                    continuation.resume()
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection)
            }
            listener.start(queue: queue)
        }

        do {
            while !Task.isCancelled && !currentStoppedState() {
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        } catch {
            listener.cancel()
            throw error
        }
    }

    func stop() {
        setStopped(true)
        listener.cancel()
    }

    private func currentStoppedState() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isStopped
    }

    private func setStopped(_ value: Bool) {
        stateLock.lock()
        isStopped = value
        stateLock.unlock()
    }

    private func handle(connection: NWConnection) {
        let state = ConnectionState()
        connection.stateUpdateHandler = { newState in
            switch newState {
            case .cancelled, .failed:
                state.cancelTimeout()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveNextChunk(on: connection, state: state)
    }

    private func send(response: BacktickMCPHTTPResponse, on connection: NWConnection, state: ConnectionState) {
        let shouldKeepAlive = (response.headers["Connection"] ?? "close").lowercased() != "close"
        connection.send(content: response.serialized(), completion: .contentProcessed { [weak self] _ in
            if shouldKeepAlive {
                state.buffer = Data()
                self?.receiveNextChunk(on: connection, state: state)
            } else {
                connection.cancel()
            }
        })
    }

    private func receiveNextChunk(on connection: NWConnection, state: ConnectionState) {
        state.scheduleTimeout(seconds: 30) {
            connection.cancel()
        }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            if let data, !data.isEmpty {
                state.buffer.append(data)
            }

            if state.buffer.count > 1_048_576 {
                state.cancelTimeout()
                self.send(
                    response: BacktickMCPHTTPResponse(
                        statusCode: 413,
                        reasonPhrase: "Content Too Large",
                        headers: [
                            "Connection": "close",
                            "Content-Type": "text/plain; charset=utf-8",
                        ],
                        body: Data("Request body exceeds the 1 MB limit.".utf8)
                    ),
                    on: connection,
                    state: state
                )
                return
            }

            switch BacktickMCPHTTPRequestParser.parse(state.buffer) {
            case .success(let request):
                state.cancelTimeout()
                Task { [weak self] in
                    guard let self else { return }
                    let response = await self.handler.response(for: request)
                    self.send(response: response, on: connection, state: state)
                }
                return

            case .failure(let message):
                state.cancelTimeout()
                self.send(
                    response: BacktickMCPHTTPResponse(
                        statusCode: 400,
                        reasonPhrase: "Bad Request",
                        headers: [
                            "Connection": "close",
                            "Content-Type": "text/plain; charset=utf-8",
                        ],
                        body: Data(message.utf8)
                    ),
                    on: connection,
                    state: state
                )
                return

            case .incomplete:
                break
            }

            if let error {
                state.cancelTimeout()
                self.send(
                    response: BacktickMCPHTTPResponse(
                        statusCode: 400,
                        reasonPhrase: "Bad Request",
                        headers: [
                            "Connection": "close",
                            "Content-Type": "text/plain; charset=utf-8",
                        ],
                        body: Data(error.localizedDescription.utf8)
                    ),
                    on: connection,
                    state: state
                )
                return
            }

            if isComplete {
                state.cancelTimeout()
                self.send(
                    response: BacktickMCPHTTPResponse(
                        statusCode: 400,
                        reasonPhrase: "Bad Request",
                        headers: [
                            "Connection": "close",
                            "Content-Type": "text/plain; charset=utf-8",
                        ],
                        body: Data("Incomplete HTTP request.".utf8)
                    ),
                    on: connection,
                    state: state
                )
                return
            }

            self.receiveNextChunk(on: connection, state: state)
        }
    }
}
