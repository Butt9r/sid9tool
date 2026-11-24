import SwiftUI

@main
struct Sid9toolApp: App {
    @StateObject private var localization = LocalizationService()
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(localization)
                .environmentObject(appState)
                .tint(.white)
        }
    }
}