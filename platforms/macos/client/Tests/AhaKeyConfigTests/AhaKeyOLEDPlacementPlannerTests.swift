import XCTest
@testable import AhaKeyConfig

final class AhaKeyOLEDPlacementPlannerTests: XCTestCase {
    func testReusesCurrentModeSlotWhenNewFrameCountStillFits() throws {
        let states = [
            pictureState(mode: 0, start: 10, length: 4, max: 30),
            pictureState(mode: 1, start: 0, length: 5, max: 30),
            pictureState(mode: 2, start: 20, length: 5, max: 30),
        ]

        let start = try AhaKeyOLEDPlacementPlanner.startIndex(
            for: .mode0,
            frameCount: 6,
            states: states
        )

        XCTAssertEqual(start, 10)
    }

    func testFindsFirstAvailableGapWhenCurrentSlotDoesNotFit() throws {
        let states = [
            pictureState(mode: 0, start: 10, length: 2, max: 30),
            pictureState(mode: 1, start: 0, length: 5, max: 30),
            pictureState(mode: 2, start: 16, length: 5, max: 30),
        ]

        let start = try AhaKeyOLEDPlacementPlanner.startIndex(
            for: .mode0,
            frameCount: 8,
            states: states
        )

        XCTAssertEqual(start, 5)
    }

    func testThrowsWhenAnimationExceedsCapacity() {
        let states = [
            pictureState(mode: 0, start: 0, length: 0, max: 10),
        ]

        XCTAssertThrowsError(
            try AhaKeyOLEDPlacementPlanner.startIndex(
                for: .mode0,
                frameCount: 11,
                states: states
            )
        ) { error in
            guard case OLEDUploadError.noAvailablePictureSlot(let needed, let max) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(needed, 11)
            XCTAssertEqual(max, 10)
        }
    }

    private func pictureState(mode: Int, start: Int, length: Int, max: Int) -> AhaKeyPictureState {
        AhaKeyPictureState(
            mode: mode,
            startIndex: start,
            picLength: length,
            frameInterval: 100,
            allModeMaxPic: max
        )
    }
}
