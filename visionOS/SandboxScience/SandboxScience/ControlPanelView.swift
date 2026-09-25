import SwiftUI

struct ControlPanelView: View {
    @Bindable var settings: SimulationSettings
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace
    
    @State private var selectedColorIndex: Int = 0
    @State private var isColorMenuOpen: Bool = false
    
    let colorNames = [
        "紅🔴", "綠🟢", "藍🔵", "黃🟡", "紫🟣", "青🩵",
        "橙🟠", "粉🩷", "棕🟤", "灰🔘", "深灰🗿", "黑⚫️",
        "洋紅🌺", "水藍💧", "靛藍🧿", "白⚪️"
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            headerSection
            Divider()
            colorMenuSection
            rulesListSection
            Divider()
            exitButtonSection
        }
        .font(.caption)
        .padding(16)
        .frame(width: 320)
        .glassBackgroundEffect()
    }
    
    // MARK: - 1. 頂部全局控制區
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
        }
    }
    
    // MARK: - 2. 主體粒子選單
    private var colorMenuSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("主體粒子")
                Spacer()
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isColorMenuOpen.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(colorNames[selectedColorIndex])
                        Image(systemName: isColorMenuOpen ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            
            if isColorMenuOpen {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 65))], spacing: 6) {
                    ForEach(0..<settings.numTypes, id: \.self) { i in
                        colorButton(for: i)
                    }
                }
                .padding(8)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
            }
        }
    }
    
    // 獨立處理按鈕樣式，避免三元運算子造成編譯器型別推導超時
    @ViewBuilder
    private func colorButton(for index: Int) -> some View {
        let btn = Button(action: {
            selectedColorIndex = index
            withAnimation { isColorMenuOpen = false }
        }) {
            Text(colorNames[index])
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .controlSize(.mini)
        
        if selectedColorIndex == index {
            btn.buttonStyle(.borderedProminent).tint(.blue)
        } else {
            btn.buttonStyle(.bordered).tint(.secondary)
        }
    }
    
    // MARK: - 3. 個別粒子引力規則設定區
    private var rulesListSection: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(0..<settings.numTypes, id: \.self) { targetIndex in
                    ruleRow(targetIndex: targetIndex)
                }
            }
            .padding(.trailing, 4)
        }
        .frame(height: 160)
    }
    
    // 使用獨立的 Binding 封裝，避免迴圈內直接推導複雜陣列索引
    private func ruleRow(targetIndex: Int) -> some View {
        let arrayIndex = selectedColorIndex * 16 + targetIndex
        let binding = Binding<Float>(
            get: { settings.rules[arrayIndex] },
            set: { settings.rules[arrayIndex] = $0 }
        )
        
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("對 \(colorNames[targetIndex])")
                Spacer()
                Text(String(format: "%.2f", binding.wrappedValue))
                    .foregroundColor(ruleColor(for: binding.wrappedValue))
            }
            Slider(value: binding, in: -1.0...1.0)
        }
    }
    
    // MARK: - 4. 底部離開按鈕區
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
    
    private func ruleColor(for value: Float) -> Color {
        if value > 0 { return .green }
        if value < 0 { return .red }
        return .primary
    }
}
