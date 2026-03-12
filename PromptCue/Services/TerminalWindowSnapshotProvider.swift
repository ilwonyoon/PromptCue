import Foundation

func enumerateTerminalWindowSnapshots() -> [SuggestedTargetWindowSnapshot] {
    guard let output = runCommand(
        executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
        arguments: [
            "-e", "tell application \"Terminal\"",
            "-e", "if not running then return \"\"",
            "-e", "set outputText to \"\"",
            "-e", "repeat with w in every window",
            "-e", "set titleText to \"\"",
            "-e", "try",
            "-e", "set titleText to custom title of w",
            "-e", "end try",
            "-e", "if titleText is \"\" then",
            "-e", "try",
            "-e", "set titleText to name of w",
            "-e", "end try",
            "-e", "end if",
            "-e", "set ttyText to \"\"",
            "-e", "try",
            "-e", "set ttyText to tty of selected tab of w",
            "-e", "end try",
            "-e", "if ttyText is not \"\" then",
            "-e", "set outputText to outputText & (id of w as text) & \"|\" & titleText & \"|\" & ttyText & linefeed",
            "-e", "end if",
            "-e", "end repeat",
            "-e", "return outputText",
            "-e", "end tell",
        ]
    ) else {
        return []
    }

    return parseTerminalWindowSnapshotOutput(
        output,
        appName: "Terminal",
        bundleIdentifier: "com.apple.Terminal"
    )
}

func enumerateITermWindowSnapshots() -> [SuggestedTargetWindowSnapshot] {
    guard let output = runCommand(
        executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
        arguments: [
            "-e", "tell application id \"com.googlecode.iterm2\"",
            "-e", "if not running then return \"\"",
            "-e", "set outputText to \"\"",
            "-e", "repeat with w in windows",
            "-e", "set sessionRef to current session of current tab of w",
            "-e", "set ttyText to \"\"",
            "-e", "set nameText to \"\"",
            "-e", "try",
            "-e", "set ttyText to tty of sessionRef",
            "-e", "end try",
            "-e", "try",
            "-e", "set nameText to name of sessionRef",
            "-e", "end try",
            "-e", "if ttyText is not \"\" then",
            "-e", "set outputText to outputText & (id of w as text) & \"|\" & nameText & \"|\" & ttyText & linefeed",
            "-e", "end if",
            "-e", "end repeat",
            "-e", "return outputText",
            "-e", "end tell",
        ]
    ) else {
        return []
    }

    return parseTerminalWindowSnapshotOutput(
        output,
        appName: "iTerm2",
        bundleIdentifier: "com.googlecode.iterm2"
    )
}

func parseTerminalWindowSnapshotOutput(
    _ output: String,
    appName: String,
    bundleIdentifier: String
) -> [SuggestedTargetWindowSnapshot] {
    output
        .components(separatedBy: .newlines)
        .compactMap { line in
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else {
                return nil
            }

            let parts = trimmedLine.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else {
                return nil
            }

            let windowID = String(parts[0])
            let windowTitle = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            let tty = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tty.isEmpty else {
                return nil
            }

            return SuggestedTargetWindowSnapshot(
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                windowTitle: windowTitle.isEmpty ? nil : windowTitle,
                sessionIdentifier: windowID,
                tty: tty
            )
        }
}
