import CoreGraphics
import Foundation

struct EntityListControlsVisibilityState: Equatable {
    static let nearTopDistance: CGFloat = 16
    static let minimumScrollVelocity: CGFloat = 500
    static let minimumDirectionalTravelDistance: CGFloat = 100
    static let directionalTravelResetInterval: TimeInterval = 0.35
    static let minimumDirectionalDelta: CGFloat = 0.25
    static let bottomOverscrollTolerance: CGFloat = 1
    static let bottomBounceSettleDistance: CGFloat = 12

    private var lastContentOffsetY: CGFloat?
    private var lastTimestamp: TimeInterval?
    private var currentScrollDirection: ScrollDirection?
    private var directionalTravelDistance: CGFloat = 0
    private var isSettlingBottomBounce = false
    private(set) var isVisible: Bool

    init(isVisible: Bool = true) {
        self.isVisible = isVisible
    }

    mutating func reset(isVisible: Bool = true) {
        lastContentOffsetY = nil
        lastTimestamp = nil
        currentScrollDirection = nil
        directionalTravelDistance = 0
        isSettlingBottomBounce = false
        self.isVisible = isVisible
    }

    mutating func update(
        contentOffsetY: CGFloat,
        contentTopInset: CGFloat,
        contentBottomLimitY: CGFloat? = nil,
        timestamp: TimeInterval
    ) -> Bool {
        defer {
            lastContentOffsetY = contentOffsetY
            lastTimestamp = timestamp
        }

        let distanceFromTop = max(0, contentOffsetY - contentTopInset)
        guard distanceFromTop > Self.nearTopDistance else {
            resetDirectionalTracking()
            isVisible = true
            return isVisible
        }

        guard let lastContentOffsetY, let lastTimestamp else {
            return isVisible
        }

        let delta = contentOffsetY - lastContentOffsetY
        let elapsed = timestamp - lastTimestamp
        if elapsed >= Self.directionalTravelResetInterval {
            resetDirectionalTracking()
        }

        if delta < -Self.minimumDirectionalDelta {
            if isRecoveringFromBottomBounce(
                lastContentOffsetY: lastContentOffsetY,
                contentBottomLimitY: contentBottomLimitY
            ) || isContinuingBottomBounceSettle(
                contentOffsetY: contentOffsetY,
                contentBottomLimitY: contentBottomLimitY
            ) {
                isSettlingBottomBounce = true
                return isVisible
            }

            isSettlingBottomBounce = false
            updateDirectionalTravel(direction: .up, distance: abs(delta))
            guard elapsed > 0 else {
                return isVisible
            }

            let upwardVelocity = abs(delta) / CGFloat(elapsed)
            if upwardVelocity >= Self.minimumScrollVelocity
                && directionalTravelDistance >= Self.minimumDirectionalTravelDistance {
                isVisible = true
            }

            return isVisible
        }

        guard delta > Self.minimumDirectionalDelta else {
            return isVisible
        }

        isSettlingBottomBounce = false
        updateDirectionalTravel(direction: .down, distance: delta)

        guard elapsed > 0 else {
            return isVisible
        }

        let downwardVelocity = delta / CGFloat(elapsed)
        if downwardVelocity >= Self.minimumScrollVelocity
            && directionalTravelDistance >= Self.minimumDirectionalTravelDistance {
            isVisible = false
        }

        return isVisible
    }

    private mutating func updateDirectionalTravel(direction: ScrollDirection, distance: CGFloat) {
        if currentScrollDirection == direction {
            directionalTravelDistance += distance
        } else {
            currentScrollDirection = direction
            directionalTravelDistance = distance
        }
    }

    private mutating func resetDirectionalTracking() {
        currentScrollDirection = nil
        directionalTravelDistance = 0
    }

    private func isRecoveringFromBottomBounce(
        lastContentOffsetY: CGFloat,
        contentBottomLimitY: CGFloat?
    ) -> Bool {
        guard let contentBottomLimitY else { return false }

        return lastContentOffsetY > contentBottomLimitY + Self.bottomOverscrollTolerance
    }

    private func isContinuingBottomBounceSettle(
        contentOffsetY: CGFloat,
        contentBottomLimitY: CGFloat?
    ) -> Bool {
        guard isSettlingBottomBounce, let contentBottomLimitY else { return false }

        return contentOffsetY >= contentBottomLimitY - Self.bottomBounceSettleDistance
    }
}

private enum ScrollDirection {
    case up
    case down
}
