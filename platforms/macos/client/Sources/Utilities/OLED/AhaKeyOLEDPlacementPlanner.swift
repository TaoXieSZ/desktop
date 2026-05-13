import Foundation

enum AhaKeyOLEDPlacementPlanner {
    private struct OccupiedRegion {
        let start: Int
        let end: Int
    }

    static func startIndex(
        for targetMode: AhaKeyModeSlot,
        frameCount: Int,
        states: [AhaKeyPictureState]
    ) throws -> Int {
        let maxCapacity = states.first?.allModeMaxPic ?? AhaKeyCommand.oledMaxFrames
        guard frameCount <= maxCapacity else {
            throw OLEDUploadError.noAvailablePictureSlot(needed: frameCount, max: maxCapacity)
        }

        let targetModeRawValue = targetMode.rawValue
        let currentState = states.first { $0.mode == targetModeRawValue }
        let occupiedRegions = states
            .filter { $0.mode != targetModeRawValue && $0.picLength > 0 }
            .map { OccupiedRegion(start: $0.startIndex, end: $0.startIndex + $0.picLength) }
            .sorted { $0.start < $1.start }

        if let currentState,
           currentState.picLength > 0,
           canPlaceRange(
               start: currentState.startIndex,
               count: frameCount,
               occupiedRegions: occupiedRegions,
               maxCapacity: maxCapacity
           )
        {
            return currentState.startIndex
        }

        if let freeStart = findFreeSpace(
            occupiedRegions: occupiedRegions,
            neededCount: frameCount,
            maxCapacity: maxCapacity
        ) {
            return freeStart
        }

        throw OLEDUploadError.noAvailablePictureSlot(needed: frameCount, max: maxCapacity)
    }

    private static func canPlaceRange(
        start: Int,
        count: Int,
        occupiedRegions: [OccupiedRegion],
        maxCapacity: Int
    ) -> Bool {
        let end = start + count
        guard start >= 0, end <= maxCapacity else { return false }
        return occupiedRegions.allSatisfy { region in
            end <= region.start || start >= region.end
        }
    }

    private static func findFreeSpace(
        occupiedRegions: [OccupiedRegion],
        neededCount: Int,
        maxCapacity: Int
    ) -> Int? {
        guard !occupiedRegions.isEmpty else { return 0 }

        if occupiedRegions[0].start >= neededCount {
            return 0
        }

        for index in 0 ..< (occupiedRegions.count - 1) {
            let gapStart = occupiedRegions[index].end
            let gapEnd = occupiedRegions[index + 1].start
            if gapEnd - gapStart >= neededCount {
                return gapStart
            }
        }

        let lastEnd = occupiedRegions.last?.end ?? 0
        if lastEnd + neededCount <= maxCapacity {
            return lastEnd
        }

        return nil
    }
}
