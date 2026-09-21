import Foundation
import Metal
import simd

class ParticleSimulator {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var clearGridPipeline: MTLComputePipelineState!
    var buildGridPipeline: MTLComputePipelineState!
    var updatePipeline: MTLComputePipelineState!
    
    var particleBuffer: MTLBuffer!
    var rulesBuffer: MTLBuffer!
    var gridBuffer: MTLBuffer!
    var vertexBuffer: MTLBuffer! // 用於儲存帶有法線的頂點
    
    let numTypes = 6
    let particlesPerType = 9000 // 總計 54000 顆
    var params: SimParams
    var totalCells: Int
    
    init?(boundsSize: Float) {
        let totalParticles = particlesPerType * numTypes
        let cellSize: Float = 0.1
        let gridDim = Int32(ceil(boundsSize / cellSize))
        self.totalCells = Int(gridDim * gridDim * gridDim)
        
        self.params = SimParams(
            leftHandPos: SIMD3<Float>(10, 10, 10), rightHandPos: SIMD3<Float>(10, 10, 10),
            gridSize: SIMD3<Int32>(gridDim, gridDim, gridDim),
            particleCount: Int32(totalParticles), dt: 0.016, friction: 0.85, boundsSize: boundsSize, numTypes: Int32(numTypes), cellSize: cellSize
        )
        
        guard let device = MTLCreateSystemDefaultDevice(), let commandQueue = device.makeCommandQueue(), let library = device.makeDefaultLibrary() else { return nil }
        self.device = device; self.commandQueue = commandQueue
        
        do {
            clearGridPipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "clearGrid")!)
            buildGridPipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "buildGrid")!)
            updatePipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "updateParticles")!)
        } catch { return nil }
        
        var rules = [Float](repeating: 0, count: numTypes * numTypes)
        for i in 0..<rules.count { rules[i] = Float.random(in: -1.0...1.0) }
        rulesBuffer = device.makeBuffer(bytes: rules, length: MemoryLayout<Float>.stride * rules.count, options: .storageModeShared)
        
        let cellByteSize = MemoryLayout<Int32>.stride * 65
        gridBuffer = device.makeBuffer(length: cellByteSize * totalCells, options: .storageModePrivate)
        
        var initialParticles = [Particle]()
        initialParticles.reserveCapacity(totalParticles)
        let halfBounds = boundsSize / 2.0
        
        for type in 0..<numTypes {
            for _ in 0..<particlesPerType {
                initialParticles.append(Particle(
                    position: SIMD3<Float>.random(in: -halfBounds...halfBounds),
                    velocity: .zero, color: .zero, type: Int32(type)
                ))
            }
        }
        particleBuffer = device.makeBuffer(bytes: initialParticles, length: MemoryLayout<Particle>.stride * totalParticles, options: .storageModeShared)
        
        // 📍 54000 顆 * 60 頂點 * 32 Bytes
        vertexBuffer = device.makeBuffer(length: totalParticles * 60 * 32, options: .storageModeShared)
    }
    
    // 📍 接收來自 UI 面板的即時參數設定
    func stepSimulation(settings: SimulationSettings) {
        
        // 1. 將 UI 上的數值即時套用到 GPU 參數結構中
        self.params.friction = settings.friction
        self.params.dt = settings.speed
        
        // 2. 如果使用者按下了「隨機重置」按鈕
        if settings.triggerRandomRules {
            var rules = [Float](repeating: 0, count: numTypes * numTypes)
            for i in 0..<rules.count { rules[i] = Float.random(in: -1.0...1.0) }
            
            // 將新產生的規則寫入已存在的 Buffer 中
            let rulesPointer = rulesBuffer.contents().bindMemory(to: Float.self, capacity: rules.count)
            for i in 0..<rules.count {
                rulesPointer[i] = rules[i]
            }
            
            // 觸發完畢後切換回 false，避免重複執行
            settings.triggerRandomRules = false
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(), let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        
        encoder.setComputePipelineState(clearGridPipeline)
        encoder.setBuffer(gridBuffer, offset: 0, index: 0)
        encoder.dispatchThreads(MTLSizeMake(totalCells, 1, 1), threadsPerThreadgroup: MTLSizeMake(min(clearGridPipeline.maxTotalThreadsPerThreadgroup, totalCells), 1, 1))
        
        encoder.setComputePipelineState(buildGridPipeline)
        encoder.setBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setBuffer(gridBuffer, offset: 0, index: 1)
        encoder.setBytes(&self.params, length: MemoryLayout<SimParams>.stride, index: 2)
        let particleGridSize = MTLSizeMake(Int(params.particleCount), 1, 1)
        let particleThreadgroup = MTLSizeMake(min(buildGridPipeline.maxTotalThreadsPerThreadgroup, Int(params.particleCount)), 1, 1)
        encoder.dispatchThreads(particleGridSize, threadsPerThreadgroup: particleThreadgroup)
        
        encoder.setComputePipelineState(updatePipeline)
        encoder.setBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setBuffer(gridBuffer, offset: 0, index: 1)
        encoder.setBytes(&self.params, length: MemoryLayout<SimParams>.stride, index: 2)
        encoder.setBuffer(rulesBuffer, offset: 0, index: 3)
        encoder.setBuffer(vertexBuffer, offset: 0, index: 4)
        encoder.dispatchThreads(particleGridSize, threadsPerThreadgroup: particleThreadgroup)
        
        encoder.endEncoding(); commandBuffer.commit(); commandBuffer.waitUntilCompleted()
    }
}
