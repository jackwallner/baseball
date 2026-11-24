import StoreKit
import SwiftUI

extension View {
    /// Calls Apple's rating prompt a few seconds after a good moment, with no
    /// question in front of it (App Review 5.6.1). Bump `moment` when the good
    /// result happens (see `ReviewMoment`).
    ///
    /// When the wait is over the screen is checked again: this view must still
    /// be on screen and nothing (sheet, alert, full-screen cover, paywall, trial
    /// pitch) may be presented over it. If something is up, this moment skips
    /// and the next one asks.
    func requestsReview(after moment: Int) -> some View {
        modifier(ReviewRequestModifier(moment: moment))
    }
}

private struct ReviewRequestModifier: ViewModifier {
    let moment: Int

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @EnvironmentObject private var store: StoreService
    @Environment(\.requestReview) private var requestReview
    /// False while onboarding or an update showcase covers the tabs.
    @Environment(\.isEnabled) private var isEnabled
    @State private var onScreen = false

    func body(content: Content) -> some View {
        content
            .onAppear { onScreen = true }
            .onDisappear { onScreen = false }
            .onChange(of: moment) { _, _ in schedule() }
    }

    private var mayAsk: Bool {
        #if DEBUG
        if DuoScreenshotMode.isSeeded { return false }
        #endif
        // RevenueCat's `rating_prompt: off` pauses the asks without a release.
        return store.isOn(.ratingPrompt)
            && ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: hasCompletedOnboarding)
    }

    private func schedule() {
        guard mayAsk else { return }
        Task { @MainActor in
            // Let the result land first.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard onScreen, isEnabled, ReviewScreen.isClear, mayAsk else { return }
            ReviewPromptTracker.markShown()
            requestReview()
        }
    }
}

enum ReviewScreen {
    /// Nothing is presented over the app. Sheets belong to the screens that
    /// raise them, so ask UIKit rather than tracking flags.
    @MainActor
    static var isClear: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .allSatisfy { $0.rootViewController?.presentedViewController == nil }
    }
}
