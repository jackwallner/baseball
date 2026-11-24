import Foundation

import RevenueCat

/// Everything RevenueCat can change without a release, read from the current
/// offering's metadata (a running Experiment's variant included). Every
/// variant ships in the binary; a missing, non-string or unknown value is the
/// control, which is today's copy. A key a switch reads must be set the same
/// on every offering, or an Experiment arm would flip it as a side effect.
/// Wording tests go through the offering metadata key `trial_cta`.
///
/// DEBUG builds can pin any key for captures: `-statscout.rc.<key> <value>`.

/// The trial button's wording, for an account that is eligible for the trial.
enum TrialCTA: String, CaseIterable, Sendable {
    static let metadataKey = "trial_cta"

    /// Control: today's copy. Onboarding and the trial pitches say
    /// "Start 7-day free trial" (the length comes from the package); the
    /// paywall says "Start Free Trial".
    case sevenDay = "seven_day"
    case my
    case your

    enum Surface {
        /// Onboarding trial page and the one-tap trial pitches: sentence case.
        case sentence
        /// The paywall button: title case.
        case titleCase
    }

    static func from(metadata: [String: Any]?) -> TrialCTA {
        RemoteConfig.value(metadataKey, in: metadata, default: .sevenDay)
    }

    func title(_ surface: Surface, trial: IntroTrial) -> String {
        switch (self, surface) {
        case (.sevenDay, .sentence): return trial.startLabel
        case (.sevenDay, .titleCase): return String(localized: "Start Free Trial")
        case (.my, .sentence): return String(localized: "Start my free trial")
        case (.my, .titleCase): return String(localized: "Start My Free Trial")
        case (.your, .sentence): return String(localized: "Start your free trial")
        case (.your, .titleCase): return String(localized: "Start Your Free Trial")
        }
    }
}

/// Remote off switches, for what is worth pausing without a release. On
/// unless the metadata says "off".
enum RemoteSwitch: String, CaseIterable, Sendable {
    /// Apple's rating prompt after a good moment.
    case ratingPrompt = "rating_prompt"
}

enum RemoteConfig {
    /// The value for `key`, or `fallback` when it is missing, not a string,
    /// or not one of the shipped variants.
    static func value<T: RawRepresentable>(_ key: String, in metadata: [String: Any]?, default fallback: T) -> T
    where T.RawValue == String {
        #if DEBUG
        if let pinned = launchOverride(key).flatMap(T.init(rawValue:)) { return pinned }
        #endif
        guard let raw = metadata?[key] as? String else { return fallback }
        return T(rawValue: raw) ?? fallback
    }

    static func isOn(_ remoteSwitch: RemoteSwitch, in metadata: [String: Any]?) -> Bool {
        #if DEBUG
        if let pinned = launchOverride(remoteSwitch.rawValue) { return pinned != "off" }
        #endif
        return (metadata?[remoteSwitch.rawValue] as? String) != "off"
    }

    #if DEBUG
    private static func launchOverride(_ key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-statscout.rc.\(key)"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
    #endif
}

extension StoreService {
    var trialCTAArm: TrialCTA { TrialCTA.from(metadata: remoteMetadata) }

    func isOn(_ remoteSwitch: RemoteSwitch) -> Bool {
        RemoteConfig.isOn(remoteSwitch, in: remoteMetadata)
    }
}
