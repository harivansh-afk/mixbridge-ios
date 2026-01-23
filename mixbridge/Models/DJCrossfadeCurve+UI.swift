import Foundation
import MixBridgeDJ

extension DJCrossfadeCurve {
    var description: String {
        switch self {
        case .linear: return "Simple straight-line fade"
        case .equalPower: return "Smooth, maintains loudness"
        case .sCurve: return "Extra smooth transitions"
        case .exponential: return "Quick drop, long tail"
        }
    }
}
