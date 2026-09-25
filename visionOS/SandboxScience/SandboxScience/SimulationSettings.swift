import Foundation
import Observation

@Observable
class SimulationSettings {
    var friction: Float = 0.85
    var speed: Float = 0.016
    
    var currentParticleCount: Float = 54000
    
    // 動態粒子種類數量 (1~16)，預設 7 種
    var numTypes: Int = 7
    
    // 將矩陣擴充為 16x16 = 256 個參數
    var rules: [Float] = {
        var initialRules = [Float](repeating: 0, count: 256)
        for i in 0..<256 {
            initialRules[i] = Float.random(in: -1.0...1.0)
        }
        return initialRules
    }()
}
