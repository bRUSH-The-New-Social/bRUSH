import Foundation
import Combine
import DeclaredAgeRange

/// Age-gates the app using Apple's Declared Age Range API (iOS 26+).
///
/// On first launch it asks the system for the user's declared age range against
/// a 13+ threshold. If the user (or their guardian) has declared an age below
/// 13, the app is blocked. If the user declines to share, or the device/account
/// is ineligible to provide a range, we fail open and rely on the Terms/EULA
/// (which state the 13+ requirement) — the choice made for this app.
///
/// A successful check is cached so we don't re-prompt on every launch.
@MainActor
final class AgeGate: ObservableObject {
    enum Status {
        case checking
        case allowed
        case blocked
    }

    @Published private(set) var status: Status = .checking

    /// Minimum age required to use the app (COPPA-aligned).
    private let minimumAge = 13
    private static let passedKey = "ageGatePassed"

    init() {
        // Skip the prompt if a prior launch already cleared the gate.
        if UserDefaults.standard.bool(forKey: Self.passedKey) {
            status = .allowed
        }
    }

    /// Runs the declared-age-range check. Safe to call repeatedly; it no-ops once
    /// the gate has been cleared.
    func verify(using request: DeclaredAgeRangeAction) async {
        guard status != .allowed else { return }

        do {
            let response = try await request(ageGates: minimumAge)
            switch response {
            case .declinedSharing:
                // User declined to share — rely on the Terms/EULA. Fail open.
                allow()
            case .sharing(let range):
                // The system buckets the user relative to the 13 gate. If the
                // declared range is entirely below 13, block; otherwise allow.
                if let upperBound = range.upperBound, upperBound < minimumAge {
                    status = .blocked
                } else {
                    allow()
                }
            }
        } catch {
            // API unavailable or account ineligible to provide a range. Fail open.
            allow()
        }
    }

    private func allow() {
        UserDefaults.standard.set(true, forKey: Self.passedKey)
        status = .allowed
    }
}
