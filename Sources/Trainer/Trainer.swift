import SwiftUI

@main
struct Trainer: App {
    @NSApplicationDelegateAdaptor(ScreenWakeController.self) private var screenWakeController
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 1180, minHeight: 780)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
