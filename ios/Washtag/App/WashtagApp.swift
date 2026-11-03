import SwiftUI
import UIKit

@main
struct WashtagApp: App {
    @State private var store = AppStore()
    @State private var passedAdGate = false

    var body: some Scene {
        WindowGroup {
            Group {
                if passedAdGate {
                    RootView()
                } else {
                    AdGateView { withAnimation { passedAdGate = true } }
                }
            }
            .environment(store)
            .tint(Theme.tub)
        }
    }
}

struct RootView: View {
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            ScanView(goToLoad: { tab = 2 })
                .tabItem { Label("Scan", systemImage: "viewfinder") }.tag(0)
            IndexView(goToLoad: { tab = 2 })
                .tabItem { Label("Index", systemImage: "list.bullet") }.tag(1)
            LoadView()
                .tabItem { Label("This load", systemImage: "washer") }.tag(2)
            HouseholdView()
                .tabItem { Label("Household", systemImage: "person.2") }.tag(3)
        }
        // Swipe down on a list or page to close the keyboard.
        .scrollDismissesKeyboard(.interactively)
        // Tap anywhere outside a text box to close the keyboard.
        .onAppear { KeyboardDismisser.shared.install() }
    }
}

/// Closes the keyboard when the user taps outside a text field. The tap is
/// watched on the whole window and never blocks buttons or other taps.
@MainActor
final class KeyboardDismisser: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismisser()
    private weak var window: UIWindow?

    func install() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        guard let target = windows.first(where: { $0.isKeyWindow }) ?? windows.first else { return }
        if window === target { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        target.addGestureRecognizer(tap)
        window = target
    }

    @objc private func handleTap() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view: UIView? = touch.view
        while let current = view {
            if current is UITextField || current is UITextView { return false }
            view = current.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
