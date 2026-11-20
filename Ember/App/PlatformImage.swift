#if canImport(UIKit)
import UIKit

/// The image type of the platform: UIImage on iPhone, NSImage on Mac.
/// Shared code (covers, save pictures) uses this name.
typealias PlatformImage = UIImage
#else
import AppKit

typealias PlatformImage = NSImage

extension NSImage {
    /// Same as UIImage's, for code shared with the iPhone app.
    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let tiff = tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }
}
#endif

import Foundation

/// The device line at the top of a game's log ("iPhone · iOS 27.2",
/// "Mac · macOS 26.1").
enum DeviceInfo {
    @MainActor static var summary: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let number = "\(version.majorVersion).\(version.minorVersion)"
        #if os(macOS)
        return "Mac · macOS \(number)"
        #else
        return "\(UIDevice.current.model) · iOS \(number)"
        #endif
    }
}
