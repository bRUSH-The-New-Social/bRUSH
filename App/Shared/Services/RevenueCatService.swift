import Foundation
import Combine
import RevenueCat

@MainActor
final class RevenueCatService: ObservableObject {
    static let shared = RevenueCatService()

    @Published var isPro = false
    @Published var currentOffering: Offering?

    private init() {
        Purchases.configure(withAPIKey: "test_oLjmfFXiqPRkuiWndRKWAngiVbT")
        Purchases.logLevel = .warn
        Task { await refreshStatus() }
    }

    func refreshStatus() async {
        do {
            let info = try await Purchases.shared.customerInfo()
            isPro = info.entitlements["pro_artist"]?.isActive == true
        } catch {}
        do {
            let offerings = try await Purchases.shared.offerings()
            currentOffering = offerings.current
        } catch {}
    }

    func logIn(userId: String) async {
        do {
            _ = try await Purchases.shared.logIn(userId)
            await refreshStatus()
        } catch {}
    }

    func logOut() async {
        do {
            _ = try await Purchases.shared.logOut()
            isPro = false
        } catch {}
    }
}
