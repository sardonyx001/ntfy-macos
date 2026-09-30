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
}
