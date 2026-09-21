import Foundation
import Observation

@Observable
class SimulationSettings {
    // 預設值與原本 Metal 中的設定相同
    var friction: Float = 0.85
    var speed: Float = 0.016
    
    // 用來觸發重新產生引力規則的開關
    var triggerRandomRules: Bool = false
}
