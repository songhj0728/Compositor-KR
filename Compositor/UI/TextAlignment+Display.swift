import SwiftUI

extension TextAlignment {
    /// `rawValue` as a localizable display name; `rawValue` itself stays the stable, unlocalized identifier.
    nonisolated var displayName: LocalizedStringKey {
        switch self {
        case .left: return "Left"
        case .center: return "Center"
        case .right: return "Right"
        }
    }
}
