import SwiftUI

/// A compact "By continuing you agree to …" line with tappable Terms and
/// Privacy Policy links. Shown on the sign-in and sign-up screens so users
/// agree to the terms (including the zero-tolerance policy for objectionable
/// user content) before creating content — an App Store requirement for
/// user-generated-content apps (Guideline 1.2).
struct LegalAgreementView: View {
    /// Leading verb, e.g. "continuing" (sign-in) or "signing up" (sign-up).
    var action: String = "continuing"

    var body: some View {
        VStack(spacing: 2) {
            Text("By \(action) you agree to our")
            HStack(spacing: 4) {
                Link("Terms of Use", destination: LegalLinks.terms)
                Text("and")
                Link("Privacy Policy", destination: LegalLinks.privacyPolicy)
            }
        }
        .font(.caption2)
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}
