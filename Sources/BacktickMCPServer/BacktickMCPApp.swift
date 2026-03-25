import Foundation
import Darwin

public enum BacktickMCPApp {
    public static func run(commandLine: [String] = CommandLine.arguments) async -> Int32 {
        do {
            let configuration = try Configuration(commandLine: commandLine)
            if configuration.showsHelp {
                writeLine(Configuration.usage, to: .standardOutput)
                return 0
            }

            let session = await MainActor.run {
                BacktickMCPServerSession(
                    databaseURL: configuration.databaseURL,
                    attachmentBaseDirectoryURL: configuration.attachmentBaseDirectoryURL
                )
            }

            switch configuration.transport {
            case .stdio:
                while let line = readLine() {
                    if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        continue
                    }

                    if let responseLine = await MainActor.run(body: { session.handleLine(line) }) {
                        writeLine(responseLine, to: .standardOutput)
                    }
                }
            case .http:
                let server = try BacktickMCPHTTPServer(
                    configuration: configuration.httpConfiguration,
                    session: session,
                    logger: { message in
                        writeLine(message, to: .standardError)
                    }
                )
                let parentMonitorTask = configuration.parentProcessIdentifier
                    .map { parentProcessIdentifier in
                        ParentProcessMonitor.startWatching(
                            parentProcessIdentifier: parentProcessIdentifier
                        ) {
                            writeLine(
                                "Backtick MCP HTTP shutting down because parent process \(parentProcessIdentifier) exited.",
                                to: .standardError
                            )
                            server.stop()
                        }
                    }
                defer {
                    parentMonitorTask?.cancel()
                }
                try await server.run()
            }

            return 0
        } catch {
            writeLine("BacktickMCP error: \(error.localizedDescription)", to: .standardError)
            writeLine(Configuration.usage, to: .standardError)
            return 1
        }
    }

    private struct Configuration {
        enum Transport: String {
            case stdio
            case http
        }

        let databaseURL: URL?
        let attachmentBaseDirectoryURL: URL?
        let showsHelp: Bool
        let transport: Transport
        let httpConfiguration: BacktickMCPHTTPConfiguration
        let parentProcessIdentifier: Int32?

        init(commandLine: [String]) throws {
            var databaseURL = ProcessInfo.processInfo.environment["PROMPTCUE_DB_PATH"].flatMap {
                URL(fileURLWithPath: $0)
            }
            var attachmentBaseDirectoryURL = ProcessInfo.processInfo.environment["PROMPTCUE_ATTACHMENTS_PATH"].flatMap {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
            var showsHelp = false
            var transport: Transport = .stdio
            var httpHost = "127.0.0.1"
            var httpPort: UInt16 = 8321
            var httpAuthMode: BacktickMCPHTTPAuthMode = .apiKey
            var httpAPIKey = ProcessInfo.processInfo.environment["PROMPTCUE_MCP_HTTP_API_KEY"]
            var httpPublicBaseURL = ProcessInfo.processInfo.environment["PROMPTCUE_MCP_HTTP_PUBLIC_BASE_URL"]
                .flatMap(URL.init(string:))
            var httpOAuthStateFileURL = ProcessInfo.processInfo.environment["PROMPTCUE_MCP_HTTP_OAUTH_STATE_PATH"]
                .flatMap { URL(fileURLWithPath: $0) }
            var httpAccessTokenLifetime = ProcessInfo.processInfo.environment["PROMPTCUE_MCP_HTTP_ACCESS_TOKEN_TTL"]
                .flatMap(TimeInterval.init)
            var parentProcessIdentifier: Int32?

            var iterator = commandLine.dropFirst().makeIterator()
            while let argument = iterator.next() {
                switch argument {
                case "--help", "-h":
                    showsHelp = true
                case "--transport":
                    guard let value = iterator.next(),
                          let parsedTransport = Transport(rawValue: value.lowercased()) else {
                        throw ConfigurationError.invalidTransport
                    }
                    transport = parsedTransport
                case "--host":
                    guard let value = iterator.next(), !value.isEmpty else {
                        throw ConfigurationError.missingValue(argument)
                    }
                    httpHost = value
                case "--port":
                    guard let value = iterator.next(),
                          let parsedPort = UInt16(value) else {
                        throw ConfigurationError.invalidPort
                    }
                    httpPort = parsedPort
                case "--auth-mode":
                    guard let value = iterator.next() else {
                        throw ConfigurationError.missingValue(argument)
                    }
                    let normalizedValue = value == "apikey" ? "apiKey" : value
                    guard let parsedAuthMode = BacktickMCPHTTPAuthMode(rawValue: normalizedValue) else {
                        throw ConfigurationError.invalidAuthMode
                    }
                    httpAuthMode = parsedAuthMode
                case "--api-key":
                    guard let value = iterator.next(), !value.isEmpty else {
                        throw ConfigurationError.missingValue(argument)
                    }
                    httpAPIKey = value
                case "--public-base-url":
                    guard let value = iterator.next(),
                          let parsedURL = URL(string: value) else {
                        throw ConfigurationError.invalidPublicBaseURL
                    }
                    httpPublicBaseURL = parsedURL
                case "--oauth-state-path":
                    guard let value = iterator.next(), !value.isEmpty else {
                        throw ConfigurationError.missingValue(argument)
                    }
                    httpOAuthStateFileURL = URL(fileURLWithPath: value)
                case "--access-token-ttl":
                    guard let value = iterator.next(),
                          let parsedLifetime = TimeInterval(value),
                          parsedLifetime > 0 else {
                        throw ConfigurationError.invalidAccessTokenLifetime
                    }
                    httpAccessTokenLifetime = parsedLifetime
                case "--parent-pid":
                    guard let value = iterator.next(),
                          let parsedProcessIdentifier = Int32(value),
                          parsedProcessIdentifier > 0 else {
                        throw ConfigurationError.invalidParentProcessIdentifier
                    }
                    parentProcessIdentifier = parsedProcessIdentifier
                case "--database-path":
                    guard let value = iterator.next(), !value.isEmpty else {
                        throw ConfigurationError.missingValue(argument)
                    }
                    databaseURL = URL(fileURLWithPath: value)
                case "--attachments-path":
                    guard let value = iterator.next(), !value.isEmpty else {
                        throw ConfigurationError.missingValue(argument)
                    }
                    attachmentBaseDirectoryURL = URL(fileURLWithPath: value, isDirectory: true)
                default:
                    throw ConfigurationError.unknownArgument(argument)
                }
            }

            self.databaseURL = databaseURL?.standardizedFileURL
            self.attachmentBaseDirectoryURL = attachmentBaseDirectoryURL?.standardizedFileURL
            self.showsHelp = showsHelp
            self.transport = transport
            self.httpConfiguration = BacktickMCPHTTPConfiguration(
                host: httpHost,
                port: httpPort,
                authMode: httpAuthMode,
                apiKey: httpAPIKey,
                publicBaseURL: httpPublicBaseURL,
                oauthStateFileURL: httpOAuthStateFileURL,
                // 24-hour fallback: see BacktickMCPHTTPConfiguration for rationale
                accessTokenLifetime: httpAccessTokenLifetime ?? 86400
            )
            self.parentProcessIdentifier = parentProcessIdentifier
        }

        static let usage = """
        Usage: BacktickMCP [--transport <stdio|http>] [--host <host>] [--port <port>] [--auth-mode <apiKey|oauth>] [--api-key <secret>] [--public-base-url <https-url>] [--oauth-state-path <path>] [--access-token-ttl <seconds>] [--parent-pid <pid>] [--database-path <path>] [--attachments-path <path>]

        Environment:
          PROMPTCUE_DB_PATH            Optional Stack database path override
          PROMPTCUE_ATTACHMENTS_PATH   Optional managed attachments directory override
          PROMPTCUE_MCP_HTTP_API_KEY   Optional HTTP API key when transport=http
          PROMPTCUE_MCP_HTTP_PUBLIC_BASE_URL Optional public HTTPS base URL for OAuth metadata
          PROMPTCUE_MCP_HTTP_OAUTH_STATE_PATH Optional OAuth state file path override for HTTP transport
          PROMPTCUE_MCP_HTTP_ACCESS_TOKEN_TTL Optional OAuth access token lifetime in seconds for HTTP transport
        """
    }

    private enum ConfigurationError: LocalizedError {
        case missingValue(String)
        case unknownArgument(String)
        case invalidPort
        case invalidTransport
        case invalidAuthMode
        case invalidPublicBaseURL
        case invalidAccessTokenLifetime
        case invalidParentProcessIdentifier

        var errorDescription: String? {
            switch self {
            case .missingValue(let flag):
                return "Missing value for \(flag)"
            case .unknownArgument(let argument):
                return "Unknown argument \(argument)"
            case .invalidPort:
                return "Invalid value for --port"
            case .invalidTransport:
                return "Invalid value for --transport"
            case .invalidAuthMode:
                return "Invalid value for --auth-mode"
            case .invalidPublicBaseURL:
                return "Invalid value for --public-base-url"
            case .invalidAccessTokenLifetime:
                return "Invalid value for --access-token-ttl"
            case .invalidParentProcessIdentifier:
                return "Invalid value for --parent-pid"
            }
        }
    }
}

private enum ParentProcessMonitor {
    static func startWatching(
        parentProcessIdentifier: Int32,
        onParentExit: @escaping @Sendable () -> Void
    ) -> Task<Void, Never> {
        Task.detached(priority: .background) {
            while !Task.isCancelled {
                if getppid() != parentProcessIdentifier {
                    onParentExit()
                    return
                }

                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}

private func writeLine(_ line: String, to handle: FileHandle) {
    guard let data = "\(line)\n".data(using: .utf8) else {
        return
    }

    handle.write(data)
}
