import SwiftUI
import AppKit

@main
struct Trainer: App {
    @NSApplicationDelegateAdaptor(ScreenWakeController.self) private var screenWakeController
    @StateObject private var viewModel = AppViewModel()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 1180, minHeight: 780)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
