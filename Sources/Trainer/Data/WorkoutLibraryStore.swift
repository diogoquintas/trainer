import Foundation

struct WorkoutLibraryStore {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    func loadWorkouts() -> [Workout] {
        guard let data = try? Data(contentsOf: libraryURL) else { return [] }
        return (try? decoder.decode([Workout].self, from: data)) ?? []
    }

    func saveWorkouts(_ workouts: [Workout]) throws {
        let directory = libraryURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(workouts)
        try data.write(to: libraryURL, options: [.atomic])
    }

    private var libraryURL: URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return baseURL
            .appendingPathComponent("Trainer", isDirectory: true)
            .appendingPathComponent("workouts.json")
    }
}
