import SwiftUI
import RevenueCatUI

struct PaywallView: View {
    @EnvironmentObject private var store: StoreService

    var body: some View {
        if let offering = store.currentOffering {
            RevenueCatUI.PaywallView(offering: offering)
        } else {
            RevenueCatUI.PaywallView()
        }
    }
}
