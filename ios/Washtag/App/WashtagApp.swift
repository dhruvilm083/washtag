import SwiftUI

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
    }
}
