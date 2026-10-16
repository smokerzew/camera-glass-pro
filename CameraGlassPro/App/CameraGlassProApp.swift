import SwiftUI

@main
struct CameraGlassProApp: App {
    init() {
        // Imported videos and exports are temporary copies; drop any left over from earlier launches.
        VideoService.purgeStaleCopies()
        try? PhotoExportService().prepareDirectory()
    }

    var body: some Scene {
        WindowGroup {
            CameraWorkspaceView()
        }
    }
}
