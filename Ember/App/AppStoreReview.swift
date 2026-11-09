import UIKit

/// Ember's page in the App Store, at "Write a Review".
enum AppStoreReview {
    /// Ember's App Store number (apps.apple.com/app/id6831097797).
    static let appID = 6_831_097_797

    static let writeReviewURL = URL(string: "https://apps.apple.com/app/id\(appID)?action=write-review")!

    /// True when the App Store opened.
    @MainActor
    static func openWriteReview() async -> Bool {
        await UIApplication.shared.open(writeReviewURL)
    }
}
