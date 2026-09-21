import SwiftUI

struct ControlPanelView: View {
    @Bindable var settings: SimulationSettings
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace
    @State private var isImmersiveSpaceOpen = false
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Particle Life 控制中樞")
                .font(.largeTitle)
                .bold()
            
            // 啟動/關閉空間的按鈕
            Toggle(isImmersiveSpaceOpen ? "關閉空間" : "啟動粒子模擬", isOn: $isImmersiveSpaceOpen)
                .toggleStyle(.button)
                .buttonStyle(.borderedProminent)
                .tint(isImmersiveSpaceOpen ? .red : .blue)
                .onChange(of: isImmersiveSpaceOpen) { _, isOpen in
                    Task {
                        if isOpen {
                            await openImmersiveSpace(id: "ParticleSpace")
                        } else {
                            await dismissImmersiveSpace()
                        }
                    }
                }
            
            Divider()
            
            // 參數控制區 (只有在啟動時才啟用)
            VStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("空氣阻力 (Friction): \(String(format: "%.3f", settings.friction))")
                    Slider(value: $settings.friction, in: 0.5...1.0)
                }
                
                VStack(alignment: .leading) {
                    Text("模擬速度 (Time Step): \(String(format: "%.3f", settings.speed))")
                    Slider(value: $settings.speed, in: 0.001...0.05)
                }
                
                Button("🎲 隨機重置引力規則") {
                    settings.triggerRandomRules = true
                }
                .buttonStyle(.bordered)
            }
            .disabled(!isImmersiveSpaceOpen) // 空間未啟動時反灰
        }
        .padding(40)
        .frame(width: 450)
        .glassBackgroundEffect() // Vision Pro 專屬的玻璃材質背景
    }
}
