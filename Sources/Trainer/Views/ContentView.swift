import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isImporting = false
    @State private var isImportingRoute = false

    private let zwoType = UTType(filenameExtension: "zwo") ?? .xml
    private let gpxType = UTType(filenameExtension: "gpx") ?? .xml

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(isImporting: $isImporting, isImportingRoute: $isImportingRoute)
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
        .fileImporter(
            isPresented: $isImportingRoute,
            allowedContentTypes: [gpxType, .xml],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task {
                await viewModel.importRoute(from: url)
            }
        }
    }
}
