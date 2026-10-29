import XCTest
@testable import FrameTimecode
#if canImport(CoreMedia)
import CoreMedia
#endif

final class TimecodeTests: XCTestCase {
    // MARK: Non-drop-frame

    func testFrameNumberRoundTrip25() throws {
        let tc = try Timecode(hours: 1, minutes: 0, seconds: 0, frames: 0, rate: .fps25)
        XCTAssertEqual(tc.frameNumber, 90_000)
        XCTAssertEqual(tc.description, "01:00:00:00")
        XCTAssertEqual(Timecode(frameNumber: 90_024, rate: .fps25).description, "01:00:00:24")
        XCTAssertEqual(Timecode(frameNumber: 90_025, rate: .fps25).description, "01:00:01:00")
    }

    func testFrameNumberRoundTrip24() throws {
        let tc = try Timecode("10:59:59:23", rate: .fps24)
        XCTAssertEqual((tc + 1).description, "11:00:00:00")
        XCTAssertEqual((tc - 23).description, "10:59:59:00")
    }

    func test23_976CountsLike24() throws {
        let tc = try Timecode("00:00:01:00", rate: .fps23_976)
        XCTAssertEqual(tc.frameNumber, 24)
        XCTAssertEqual(FrameRate.fps23_976.description, "23.976")
    }

    func testFramesOutOfRange() {
        XCTAssertThrowsError(try Timecode("00:00:00:25", rate: .fps25)) { error in
            XCTAssertEqual(error as? TimecodeError, .outOfRange)
        }
        XCTAssertThrowsError(try Timecode("00:60:00:00", rate: .fps25))
        XCTAssertThrowsError(try Timecode("24:00:00:00", rate: .fps25))
    }

    func testWrapsAround24Hours() throws {
        let last = try Timecode("23:59:59:24", rate: .fps25)
        XCTAssertEqual((last + 1).description, "00:00:00:00")
        XCTAssertEqual((Timecode.zero(rate: .fps25) - 1).description, "23:59:59:24")
    }

    // MARK: Drop-frame

    func testDropFrameSkipsFrameNumbersAtMinute() throws {
        let rate = FrameRate.fps29_97DF
        let before = try Timecode("00:00:59;29", rate: rate)
        XCTAssertEqual(before.frameNumber, 1799)
        XCTAssertEqual((before + 1).description, "00:01:00;02")
    }

    func testDropFrameKeepsTenthMinute() throws {
        let rate = FrameRate.fps29_97DF
        let before = try Timecode("00:09:59;29", rate: rate)
        XCTAssertEqual((before + 1).description, "00:10:00;00")
        XCTAssertEqual((before + 1).frameNumber, 17_982)
    }

    func testDropFrameRejectsMissingNumbers() {
        XCTAssertThrowsError(try Timecode("00:01:00;00", rate: .fps29_97DF)) { error in
            XCTAssertEqual(error as? TimecodeError, .droppedFrameNumber)
        }
        XCTAssertNoThrow(try Timecode("00:10:00;00", rate: .fps29_97DF))
    }

    func testDropFrameRoundTripEveryFrameOfFirstHour() {
        let rate = FrameRate.fps29_97DF
        for n in stride(from: 0, to: 107_892, by: 7) {
            let tc = Timecode(frameNumber: n, rate: rate)
            let parsed = try? Timecode(tc.description, rate: rate)
            XCTAssertEqual(parsed?.frameNumber, n, "frame \(n) → \(tc)")
        }
    }

    func testDropFrame59_94() throws {
        let rate = FrameRate.fps59_94DF
        let before = try Timecode("00:00:59;59", rate: rate)
        XCTAssertEqual((before + 1).description, "00:01:00;04")
    }

    func testFramesPerDay() {
        XCTAssertEqual(FrameRate.fps25.framesPerDay, 2_160_000)
        XCTAssertEqual(FrameRate.fps29_97DF.framesPerDay, 2_589_408)
    }

    // MARK: Parsing

    func testParsesSeparators() throws {
        XCTAssertEqual(try Timecode("01:02:03:04", rate: .fps25).description, "01:02:03:04")
        XCTAssertEqual(try Timecode("01.02.03.04", rate: .fps25).description, "01:02:03:04")
        XCTAssertEqual(try Timecode("1:2:3:4", rate: .fps25).description, "01:02:03:04")
        XCTAssertEqual(try Timecode("10:05", rate: .fps25).description, "00:00:10:05")
    }

    func testParsesRightAlignedDigits() throws {
        XCTAssertEqual(try Timecode("1005", rate: .fps25).description, "00:00:10:05")
        XCTAssertEqual(try Timecode("01000000", rate: .fps25).description, "01:00:00:00")
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try Timecode("", rate: .fps25))
        XCTAssertThrowsError(try Timecode("ab:cd", rate: .fps25))
        XCTAssertThrowsError(try Timecode("123456789", rate: .fps25))
        XCTAssertThrowsError(try Timecode("1:2:3:4:5", rate: .fps25))
        XCTAssertThrowsError(try Timecode("٣", rate: .fps25))
    }

    // MARK: Frame rate detection

    func testDetectsStandardRates() {
        XCTAssertEqual(FrameRate.detect(fps: 23.976), .fps23_976)
        XCTAssertEqual(FrameRate.detect(fps: 24.0), .fps24)
        XCTAssertEqual(FrameRate.detect(fps: 25.0), .fps25)
        XCTAssertEqual(FrameRate.detect(fps: 29.97, dropFrame: true), .fps29_97DF)
        XCTAssertEqual(FrameRate.detect(fps: 50.0), .fps50)
        // Drop-frame не бывает при 25 fps.
        XCTAssertEqual(FrameRate.detect(fps: 25.0, dropFrame: true), .fps25)
    }

    func testFrameRateFromTimecodeTrackDuration() {
        XCTAssertEqual(FrameRate.fromFrameDuration(value: 1001, timescale: 24000, quanta: 24, dropFrame: false), .fps23_976)
        XCTAssertEqual(FrameRate.fromFrameDuration(value: 100, timescale: 2500, quanta: 25, dropFrame: false), .fps25)
        XCTAssertEqual(FrameRate.fromFrameDuration(value: 1001, timescale: 30000, quanta: 30, dropFrame: true), .fps29_97DF)
    }

    #if canImport(CoreMedia)
    func testFrameIndexFromTime() {
        let rate = FrameRate.fps23_976
        for index in [0, 1, 23, 24, 1000, 86_399] {
            XCTAssertEqual(rate.frameIndex(at: rate.time(forFrame: index)), index)
        }
        // Время в другой шкале (600 — типичная для QuickTime) округляется к правильному кадру.
        XCTAssertEqual(FrameRate.fps25.frameIndex(at: CMTime(value: 24, timescale: 600)), 1)
        XCTAssertEqual(FrameRate.fps25.frameIndex(at: CMTime(value: 23, timescale: 600)), 0)
    }
    #endif
}
