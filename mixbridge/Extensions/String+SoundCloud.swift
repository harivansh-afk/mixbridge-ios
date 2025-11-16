import Foundation

extension String {
    /// Upgrade SoundCloud artwork URL from low-quality to high-quality
    /// Replaces "-large" (100x100) with "-t500x500" (500x500)
    func upgradeArtworkQuality() -> String {
        return self.replacingOccurrences(of: "-large", with: "-t500x500")
    }

    /// Get specific size of SoundCloud artwork
    func soundCloudArtwork(size: SoundCloudArtworkSize) -> String {
        return self.replacingOccurrences(of: "-large", with: size.rawValue)
    }
}

enum SoundCloudArtworkSize: String {
    case tiny = "-t67x67"          // 67x67
    case small = "-t200x200"       // 200x200
    case medium = "-t300x300"      // 300x300
    case large = "-t500x500"       // 500x500
    case original = "-large"       // 100x100 (default from API)
}
