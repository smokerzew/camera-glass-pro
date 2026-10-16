import Foundation

/// A saved adjustment recipe ("My Styles"), stored as JSON in UserDefaults.
struct StylePreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var adjustments: PhotoAdjustmentState

    static let storageKey = "settings.stylePresets"

    static func load(from defaults: UserDefaults) -> [StylePreset] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([StylePreset].self, from: data)) ?? []
    }

    static func save(_ presets: [StylePreset], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
