import AppKit
import XCTest
@testable import Prompt_Cue

#if DEBUG
@MainActor
final class AppCoordinatorTests: XCTestCase {
    func testStatusMenuIncludesQAAccessOverrideSubmenu() throws {
        let coordinator = AppCoordinator()

        let menu = coordinator.makeStatusMenu()
        let submenu = try qaAccessOverrideSubmenu(from: menu)

        XCTAssertEqual(
            submenu.items.map(\.title),
            ["Live", "Trial", "Expired", "Rollback", "Licensed"]
        )
        XCTAssertEqual(
            submenu.items.compactMap { $0.representedObject as? String },
            ["live", "trial", "expired", "rollback", "licensed"]
        )
        XCTAssertEqual(
            submenu.items.filter { $0.state == .on }.map(\.title),
            ["Live"]
        )
    }

    func testSelectingQAAccessOverrideMenuItemUpdatesCheckmarks() throws {
        let coordinator = AppCoordinator()

        let menu = coordinator.makeStatusMenu()
        let submenu = try qaAccessOverrideSubmenu(from: menu)
        let liveItem = try menuItem(named: "Live", in: submenu)
        let expiredItem = try menuItem(named: "Expired", in: submenu)

        let expiredAction = try XCTUnwrap(expiredItem.action)
        coordinator.perform(expiredAction, with: expiredItem)

        XCTAssertEqual(expiredItem.state, .on)
        XCTAssertEqual(liveItem.state, .off)

        let liveAction = try XCTUnwrap(liveItem.action)
        coordinator.perform(liveAction, with: liveItem)

        XCTAssertEqual(liveItem.state, .on)
        XCTAssertEqual(expiredItem.state, .off)
    }

    private func qaAccessOverrideSubmenu(from menu: NSMenu) throws -> NSMenu {
        try XCTUnwrap(menu.item(withTitle: "QA Access Override")?.submenu)
    }

    private func menuItem(named title: String, in menu: NSMenu) throws -> NSMenuItem {
        try XCTUnwrap(menu.item(withTitle: title))
    }
}
#endif
