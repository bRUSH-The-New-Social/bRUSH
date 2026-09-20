import SwiftUI
import RevenueCat
import RevenueCatUI

struct ProPaywallView: View {
    @EnvironmentObject private var rcService: RevenueCatService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PaywallView()
            .onPurchaseCompleted { customerInfo in
                rcService.isPro = customerInfo.entitlements["pro_artist"]?.isActive == true
                if rcService.isPro { dismiss() }
            }
            .onRestoreCompleted { customerInfo in
                rcService.isPro = customerInfo.entitlements["pro_artist"]?.isActive == true
                if rcService.isPro { dismiss() }
            }
    }
}
