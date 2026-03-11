import Foundation

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

            while let line = readLine() {
                if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continue
                }

                if let responseLine = await MainActor.run(body: { session.handleLine(line) }) {
                    writeLine(responseLine, to: .standardOutput)
                }
            }

            return 0
        } catch {
            writeLine("BacktickMCP error: \(error.localizedDescription)", to: .standardError)
            writeLine(Configuration.usage, to: .standardError)
            return 1
        }
    }

    private struct Configuration {
        let databaseURL: URL?
        let attachmentBaseDirectoryURL: URL?
        let showsHelp: Bool

        init(commandLine: [String]) throws {
            var databaseURL = ProcessInfo.processInfo.environment["PROMPTCUE_DB_PATH"].flatMap {
                URL(fileURLWithPath: $0)
            }
            var attachmentBaseDirectoryURL = ProcessInfo.processInfo.environment["PROMPTCUE_ATTACHMENTS_PATH"].flatMap {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
            var showsHelp = false

            var iterator = commandLine.dropFirst().makeIterator()
            while let argument = iterator.next() {
                switch argument {
                case "--help", "-h":
                    showsHelp = true
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
        }

        static let usage = """
        Usage: BacktickMCP [--database-path <path>] [--attachments-path <path>]

        Environment:
          PROMPTCUE_DB_PATH            Optional Stack database path override
          PROMPTCUE_ATTACHMENTS_PATH   Optional managed attachments directory override
        """
    }

    private enum ConfigurationError: LocalizedError {
        case missingValue(String)
        case unknownArgument(String)

        var errorDescription: String? {
            switch self {
            case .missingValue(let flag):
                return "Missing value for \(flag)"
            case .unknownArgument(let argument):
                return "Unknown argument \(argument)"
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
