import Foundation
import Observation

@Observable
class SimulationSettings {
    // 📍 全域物理與互動參數
    var repelForce: Float = 2.0
    var forceMultiplier: Float = 1.0
    var friction: Float = 0.85
    var speed: Float = 0.016
    
    var currentParticleCount: Float = 54000
    var numTypes: Int = 7
    
    // 底層互動矩陣 (保留隨機性，但不再於 UI 顯示)
    var rules: [Float] = {
        var initialRules = [Float](repeating: 0, count: 256)
        for i in 0..<256 {
            initialRules[i] = Float.random(in: -1.0...1.0)
        }
        return initialRules
    }()
}
