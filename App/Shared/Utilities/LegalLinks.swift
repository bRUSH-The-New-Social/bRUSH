import Foundation

/// Central place for the app's legal/policy URLs so they can be referenced from
/// the sign-in and sign-up screens (and updated in one spot).
enum LegalLinks {
    /// Privacy policy. Hosted at the marketing site's `#privacy` anchor.
    static let privacyPolicy = URL(string: "https://brushapp.netlify.app/#privacy")!

    /// Terms of Use / EULA. Same site, `#terms` anchor.
    static let terms = URL(string: "https://brushapp.netlify.app/#terms")!
}
