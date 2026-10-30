import XCTest

/// Аппаратная клавиатура: клавиши плеера и печать в поле комментария не должны мешать друг другу.
/// Нужен симулятор, в котором уже открыто видео (приложение открывает последнее при запуске).
final class KeyboardTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    private var timecode: XCUIElement { app.descendants(matching: .any)["currentTimecode"].firstMatch }
    private var commentField: XCUIElement { app.descendants(matching: .any)["commentField"].firstMatch }

    /// → сдвигает на кадр, если клавиши сейчас у плеера.
    private func assertArrowSteps(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let before = timecode.label
        app.typeKey(.rightArrow, modifierFlags: [])
        let changed = NSPredicate(format: "label != %@", before)
        let result = XCTWaiter.wait(for: [expectation(for: changed, evaluatedWith: timecode)], timeout: 2)
        XCTAssertEqual(result, .completed, message, file: file, line: line)
    }

    func testPlayerKeysAndCommentTyping() {
        XCTAssertTrue(timecode.waitForExistence(timeout: 15), "Open a video in the simulator first")

        assertArrowSteps("Arrow keys should drive the player on launch")

        commentField.tap()
        sleep(1)
        let before = timecode.label
        // Цифры печатаются в любой раскладке; пробел — та самая клавиша Play/Stop.
        app.typeKey("1", modifierFlags: [])
        app.typeKey(" ", modifierFlags: [])
        app.typeKey("2", modifierFlags: [])
        sleep(1)
        XCTAssertEqual(commentField.value as? String, "1 2", "Typing should go into the comment field")
        XCTAssertEqual(timecode.label, before, "Typing a comment must not move the player")

        app.typeKey(.escape, modifierFlags: [])
        sleep(1)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)).tap()
        assertArrowSteps("Keys should return to the player after tapping the video")

        app.buttons["drawButton"].tap()
        app.buttons["drawButton"].tap()
        assertArrowSteps("Keys should return to the player after leaving drawing mode")

        app.typeKey(" ", modifierFlags: [])
        sleep(1)
        app.typeKey(" ", modifierFlags: [])
        XCTAssertNotEqual(timecode.label, before, "Space should play")
    }
}
