import Foundation
import PromptCueCore

struct TerminalSessionContext {
    let tty: String
    let sessionIdentifier: String?
}

struct GitContextSnapshot {
    let repositoryRoot: String
    let repositoryName: String
    let branch: String?
}

func buildDetailedSuggestedTarget(
    appName: String,
    bundleIdentifier: String,
    fallbackWindowTitle: String?,
    capturedAt: Date,
    sessionContext: TerminalSessionContext? = nil
) -> CaptureSuggestedTarget? {
    let resolvedSessionContext = sessionContext ?? resolveTerminalSessionContext(bundleIdentifier: bundleIdentifier)
    let currentWorkingDirectory = resolvedSessionContext.flatMap { resolveCurrentWorkingDirectory(forTTY: $0.tty) }
    let gitContext = currentWorkingDirectory.flatMap(resolveGitContext(for:))

    return CaptureSuggestedTarget(
        appName: appName,
        bundleIdentifier: bundleIdentifier,
        windowTitle: fallbackWindowTitle,
        sessionIdentifier: resolvedSessionContext?.sessionIdentifier,
        terminalTTY: resolvedSessionContext?.tty,
        currentWorkingDirectory: currentWorkingDirectory,
        repositoryRoot: gitContext?.repositoryRoot,
        repositoryName: gitContext?.repositoryName,
        branch: gitContext?.branch,
        capturedAt: capturedAt,
        confidence: currentWorkingDirectory == nil ? .low : .high
    )
}

func resolveTerminalSessionContext(bundleIdentifier: String) -> TerminalSessionContext? {
    switch bundleIdentifier {
    case "com.apple.Terminal":
        guard let tty = runCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: [
                "-e", "tell application \"Terminal\"",
                "-e", "if not running then return \"\"",
                "-e", "return tty of selected tab of front window",
                "-e", "end tell",
            ]
        ) else {
            return nil
        }

        return TerminalSessionContext(tty: tty, sessionIdentifier: tty)

    case "com.googlecode.iterm2":
        guard let output = runCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: [
                "-e", "tell application id \"com.googlecode.iterm2\"",
                "-e", "if not running then return \"\"",
                "-e", "tell current session of current window",
                "-e", "set ttyValue to tty",
                "-e", "set sessionName to name",
                "-e", "return ttyValue & linefeed & sessionName",
                "-e", "end tell",
                "-e", "end tell",
            ]
        ) else {
            return nil
        }

        let parts = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let tty = parts.first else {
            return nil
        }

        return TerminalSessionContext(
            tty: tty,
            sessionIdentifier: parts.dropFirst().first
        )

    default:
        return nil
    }
}

func resolveCurrentWorkingDirectory(forTTY tty: String) -> String? {
    let ttyName = URL(fileURLWithPath: tty).lastPathComponent
    guard !ttyName.isEmpty,
          let processesOutput = runCommand(
            executableURL: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-t", ttyName, "-o", "pid=,comm="]
          ) else {
        return nil
    }

    let processLines = processesOutput
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    guard let pid = processLines.last?.split(whereSeparator: \.isWhitespace).first else {
        return nil
    }

    guard let lsofOutput = runCommand(
        executableURL: URL(fileURLWithPath: "/usr/sbin/lsof"),
        arguments: ["-a", "-p", String(pid), "-d", "cwd", "-Fn"]
    ) else {
        return nil
    }

    return lsofOutput
        .components(separatedBy: .newlines)
        .first(where: { $0.hasPrefix("n") })
        .map { String($0.dropFirst()) }
}

func resolveGitContext(for currentWorkingDirectory: String) -> GitContextSnapshot? {
    guard let repositoryRoot = runCommand(
        executableURL: URL(fileURLWithPath: "/usr/bin/git"),
        arguments: ["-C", currentWorkingDirectory, "rev-parse", "--show-toplevel"]
    ) else {
        return nil
    }

    let repositoryName = URL(fileURLWithPath: repositoryRoot).lastPathComponent
    let branch = runCommand(
        executableURL: URL(fileURLWithPath: "/usr/bin/git"),
        arguments: ["-C", currentWorkingDirectory, "branch", "--show-current"]
    )

    return GitContextSnapshot(
        repositoryRoot: repositoryRoot,
        repositoryName: repositoryName,
        branch: branch?.isEmpty == true ? nil : branch
    )
}
