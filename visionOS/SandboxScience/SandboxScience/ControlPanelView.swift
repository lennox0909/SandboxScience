import SwiftUI

struct ControlPanelView: View {
    @Bindable var settings: SimulationSettings
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace
    
    @State private var selectedColorIndex: Int = 0
    
    // 擴充為 16 種顏色
    let colorNames = [
        "紅🔴", "綠🟢", "藍🔵", "黃🟡", "紫🟣", "青🩵",
        "橙🟠", "粉🩷", "棕🟤", "灰🔘", "深灰🗿", "黑⚫️",
        "洋紅🌺", "水藍💧", "靛藍🧿", "白⚪️"
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            Text("粒子控制中樞")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("粒子數量")
                    Spacer()
                    Text("\(Int(settings.currentParticleCount))").foregroundColor(.cyan)
                }
                Slider(value: $settings.currentParticleCount, in: 1000...54000, step: 1000)
            }
            
            // 粒子種類數量調整
            Stepper("粒子種類: \(settings.numTypes)", value: $settings.numTypes, in: 1...16)
                .onChange(of: settings.numTypes) { _, newValue in
                    if selectedColorIndex >= newValue {
                        selectedColorIndex = max(0, newValue - 1)
                    }
                }
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("阻力: \(String(format: "%.2f", settings.friction))")
                    Slider(value: $settings.friction, in: 0.5...0.99)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("速度: \(String(format: "%.3f", settings.speed))")
                    Slider(value: $settings.speed, in: 0.001...0.05)
                }
            }
            
            Divider()
            
            Picker("主體粒子", selection: $selectedColorIndex) {
                ForEach(0..<settings.numTypes, id: \.self) { i in
                    Text(colorNames[i]).tag(i)
                }
            }
            .pickerStyle(.menu) // 改為下拉選單避免版面爆炸
            
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(0..<settings.numTypes, id: \.self) { targetIndex in
                        // 固定以 16 為 Stride
                        let arrayIndex = selectedColorIndex * 16 + targetIndex
                        
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text("對 \(colorNames[targetIndex])")
                                Spacer()
                                Text(String(format: "%.2f", settings.rules[arrayIndex]))
                                    .foregroundColor(settings.rules[arrayIndex] > 0 ? .green : (settings.rules[arrayIndex] < 0 ? .red : .primary))
                            }
                            Slider(value: $settings.rules[arrayIndex], in: -1.0...1.0)
                        }
                    }
                }
                .padding(.trailing, 4)
            }
            .frame(height: 160)
            
            Divider()
            
            Button(action: {
                Task { await dismissImmersiveSpace() }
            }) {
                Label("離開粒子空間", systemImage: "xmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .font(.caption)
        .padding(16)
        .frame(width: 320)
        .glassBackgroundEffect()
    }
}
