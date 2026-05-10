import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isImporting = false

    private let zwoType = UTType(filenameExtension: "zwo") ?? .xml

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(isImporting: $isImporting)
                .frame(minWidth: 270)
        } detail: {
            WorkoutScreen(engine: viewModel.engine)
                .id(viewModel.workout.id)
        }
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarBackground(Color(nsColor: .windowBackgroundColor), for: .windowToolbar)
        .task {
            await viewModel.scanAndConnectSimulationDevices()
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [zwoType, .xml],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            viewModel.importWorkout(from: url)
        }
    }
}
