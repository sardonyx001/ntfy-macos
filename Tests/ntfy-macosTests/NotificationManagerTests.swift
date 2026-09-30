import XCTest
import AppKit
@testable import ntfy_macos

final class NotificationManagerTests: XCTestCase {
    /// UNNotificationAttachment only moves its source file into the notification
    /// data store when the notification is actually delivered (center.add), not at
    /// init time — deleting the file immediately after creating the attachment
    /// races that later move and breaks delivery ("Failed to move attachment file
    /// into data store").
    func testCreateAttachmentDoesNotDeleteFileImmediately() {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        guard let attachment = NotificationManager.shared.createAttachment(from: image) else {
            XCTFail("expected an attachment to be created")
            return
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: attachment.url.path))
    }

    // MARK: - Default-tap behavior: content window vs. opening a URL

    /// No explicit click target was set (neither a config click_url nor a message
    /// `Click:` header) — tapping the notification should show the content in a
    /// native window the user can copy, not open the raw topic URL in a browser.
    func testShouldShowContentWindowWhenNoExplicitClickTarget() {
        XCTAssertTrue(NotificationManager.shouldShowContentWindow(isCustomClickUrl: false, clickUrl: "https://ntfy.sh"))
    }

    /// An explicit click target was set (config click_url or message `Click:` header) —
    /// tapping should open it, honoring what the sender asked for.
    func testShouldNotShowContentWindowWhenExplicitClickTargetSet() {
        XCTAssertFalse(NotificationManager.shouldShowContentWindow(isCustomClickUrl: true, clickUrl: "https://example.com"))
    }

    /// Click is explicitly disabled for the topic (empty clickUrl, not custom) —
    /// tapping should do nothing, not fall back to a content window.
    func testShouldNotShowContentWindowWhenClickDisabled() {
        XCTAssertFalse(NotificationManager.shouldShowContentWindow(isCustomClickUrl: false, clickUrl: ""))
    }
}
