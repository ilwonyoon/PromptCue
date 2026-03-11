import BacktickMCPServer
import Darwin

@main
struct BacktickMCPMain {
    static func main() async {
        Darwin.exit(await BacktickMCPApp.run())
    }
}
