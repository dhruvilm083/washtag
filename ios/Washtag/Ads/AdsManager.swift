@preconcurrency import GoogleMobileAds
import AppTrackingTransparency
import UIKit
import UserMessagingPlatform

/// Consent (UMP), tracking prompt (ATT) and the launch ad (AdMob App Open format).
///
/// Why App Open and not an interstitial or rewarded ad:
/// - AdMob policy does not allow interstitials on app load; App Open is the format built for launch screens.
/// - Rewarded ads must be opt-in, so they can't be the forced gate.
/// - Apple guideline 2.5.18 requires a visible close/skip button, so the ad can't be unskippable.
@MainActor
final class AdsManager: NSObject, ObservableObject {
    static let shared = AdsManager()

    @Published private(set) var isShowingAd = false

    private var appOpenAd: AppOpenAd?
    private var loadTime: Date?
    private var isLoading = false
    private var started = false
    private var onFinish: (() -> Void)?

    private let adUnitID = Bundle.main.object(forInfoDictionaryKey: "WashtagAppOpenAdUnit") as? String ?? ""

    var isAdReady: Bool { isAdFresh }
    var canRequestAds: Bool { ConsentInformation.shared.canRequestAds }
    var privacyOptionsRequired: Bool { ConsentInformation.shared.privacyOptionsRequirementStatus == .required }

    /// Call once per launch. Gathers consent (shows Google's form in the EEA/UK), then the ATT prompt, then starts the SDK.
    func prepare() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters()) { _ in
                Task { @MainActor in
                    try? await ConsentForm.loadAndPresentIfRequired(from: nil)
                    cont.resume()
                }
            }
        }
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
        guard canRequestAds else { return }
        if !started { started = true; MobileAds.shared.start(completionHandler: nil) }
        await loadAd()
    }

    func loadAd() async {
        guard !isLoading, !isAdFresh, canRequestAds, !adUnitID.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            appOpenAd = try await AppOpenAd.load(with: adUnitID, request: Request())
            appOpenAd?.fullScreenContentDelegate = self
            loadTime = Date()
        } catch {
            appOpenAd = nil
            loadTime = nil
        }
    }

    /// Shows the ad if one is ready, then calls `completion` when it closes. If no ad is ready,
    /// calls `completion` straight away — the app must never be stuck behind an ad that didn't load.
    func showIfAvailable(completion: @escaping () -> Void) {
        guard !isShowingAd else { return }
        guard isAdFresh, let ad = appOpenAd else {
            completion()
            Task { await loadAd() }
            return
        }
        onFinish = completion
        isShowingAd = true
        ad.present(from: nil)
    }

    func presentPrivacyOptions() async {
        try? await ConsentForm.presentPrivacyOptionsForm(from: nil)
    }

    private var isAdFresh: Bool {
        guard appOpenAd != nil, let loadTime else { return false }
        return Date().timeIntervalSince(loadTime) < 4 * 3600 // App Open ads expire after 4 hours
    }

    private func finish() {
        appOpenAd = nil
        isShowingAd = false
        let done = onFinish
        onFinish = nil
        done?()
        Task { await loadAd() }
    }
}

extension AdsManager: FullScreenContentDelegate {
    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in self.finish() }
    }
}
