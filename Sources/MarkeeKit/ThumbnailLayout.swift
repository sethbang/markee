import CoreGraphics

/// Largest page-shaped rectangle (width / height == `pageAspect`) that fits
/// inside `maximumSize`. Returned size never exceeds the budget in either
/// dimension.
public func thumbnailContextSize(maximumSize: CGSize, pageAspect: CGFloat) -> CGSize {
    guard maximumSize.width > 0, maximumSize.height > 0, pageAspect > 0 else {
        return .zero
    }
    // Start by pinning height, derive width from the aspect.
    var width = maximumSize.height * pageAspect
    var height = maximumSize.height
    // If that overflows the width budget, pin width instead.
    if width > maximumSize.width {
        width = maximumSize.width
        height = width / pageAspect
    }
    return CGSize(width: width, height: height)
}
