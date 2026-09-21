import SwiftUI

@main
struct SandboxScienceApp: App {
    // 建立唯一一份設定實例，讓 UI 和 ImmersiveView 共享
    @State private var settings = SimulationSettings()
    
    var body: some Scene {
        // 1. 啟動時預設顯示的 2D 懸浮面板
        WindowGroup {
            ControlPanelView(settings: settings)
        }
        .windowStyle(.plain)

        // 2. 背景的 3D 沉浸空間 (ID 要和 ControlPanel 呼叫的一致)
        ImmersiveSpace(id: "ParticleSpace") {
            ImmersiveView(settings: settings) // 把設定傳遞進去
        }
    }
}
