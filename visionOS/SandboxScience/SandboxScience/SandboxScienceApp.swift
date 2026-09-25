import SwiftUI

@main
struct SandboxScienceApp: App {
    @State private var settings = SimulationSettings()
    @State private var appModel = AppModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
        }
        .windowStyle(.plain)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView(settings: settings)
                .environment(appModel)
        }
    }
}
