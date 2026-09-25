import SwiftUI

struct ControlPanelView: View {
    @Bindable var settings: SimulationSettings
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace
    
    var body: some View {
        VStack(spacing: 12) {
            headerSection
            Divider()
            interactionSection
            Divider()
            exitButtonSection
        }
        .font(.caption)
        .padding(16)
        .frame(width: 320)
        .glassBackgroundEffect()
    }
    
    // MARK: - 1. 頂部全局數量與種類
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("粒子控制中樞").font(.headline)
            
            HStack {
                Text("粒子數量")
                Spacer()
                Text("\(Int(settings.currentParticleCount))").foregroundColor(.cyan)
            }
            Slider(value: $settings.currentParticleCount, in: 1000...54000, step: 1000)
            
            Stepper("粒子種類: \(settings.numTypes)", value: $settings.numTypes, in: 1...16)
        }
    }
    
    // MARK: - 2. 核心互動參數控制 (取代舊版個別矩陣)
    private var interactionSection: some View {
        VStack(spacing: 12) {
            // 排斥力
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("排斥力 (Repel Force)")
                    Spacer()
                    Text(String(format: "%.2f", settings.repelForce))
                }
                Slider(value: $settings.repelForce, in: 0.01...4.0, step: 0.01)
                Text("調整粒子互相排斥的力度。較高的數值會增加分離距離。")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            // 引力倍率
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("引力倍率 (Force Multiplier)")
                    Spacer()
                    Text(String(format: "%.2f", settings.forceMultiplier))
                }
                Slider(value: $settings.forceMultiplier, in: 0.01...2.0, step: 0.01)
                Text("縮放粒子間的互動引力。較高的數值使作用力更強，粒子移動更快。")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            // 摩擦力
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("摩擦力 (Friction)")
                    Spacer()
                    Text(String(format: "%.2f", settings.friction))
                }
                Slider(value: $settings.friction, in: 0.0...1.0, step: 0.01)
                Text("控制摩擦力使粒子減速的程度。較高的數值會降低速度並有助於穩定系統。")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - 3. 底部離開按鈕
    private var exitButtonSection: some View {
        Button(action: {
            Task { await dismissImmersiveSpace() }
        }) {
            Label("離開粒子空間", systemImage: "xmark.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }
}
