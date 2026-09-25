import Foundation
import Metal
import simd
import ARKit

class ParticleSimulator {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var clearGridPipeline: MTLComputePipelineState!
    var buildGridPipeline: MTLComputePipelineState!
    var updatePipeline: MTLComputePipelineState!
    
    var particleBuffer: MTLBuffer!
    var rulesBuffer: MTLBuffer!
    var gridBuffer: MTLBuffer!
    var vertexBuffer: MTLBuffer!
    
    var sceneMeshBuffer: MTLBuffer?
    var sceneTriangleCount: Int32 = 0
    private var meshAnchors: [UUID: [SceneTriangle]] = [:]
    
    var anchorBoundsBuffer: MTLBuffer?
    var anchorCount: Int32 = 0
    
    var leftHandARKitPos = SIMD3<Float>(10, 10, 10)
    var rightHandARKitPos = SIMD3<Float>(10, 10, 10)
    var prevLeftHandARKitPos = SIMD3<Float>(10, 10, 10)
    var prevRightHandARKitPos = SIMD3<Float>(10, 10, 10)
    
    let maxTypes = 16
    let particlesPerType = 3375
    var params: SimParams
    var totalCells: Int
    
    init?(boundsSize: Float) {
        let totalParticles = particlesPerType * maxTypes
        let cellSize: Float = 0.1
        let gridDim = Int32(ceil(boundsSize / cellSize))
        self.totalCells = Int(gridDim * gridDim * gridDim)
        
        let spawnCenter = SIMD3<Float>(0, 1.2, -0.6)
        
        self.params = SimParams(
            leftHandPos: SIMD3<Float>(10, 10, 10), rightHandPos: SIMD3<Float>(10, 10, 10),
            prevLeftHandPos: SIMD3<Float>(10, 10, 10), prevRightHandPos: SIMD3<Float>(10, 10, 10),
            gridSize: SIMD3<Int32>(gridDim, gridDim, gridDim),
            particleCount: Int32(totalParticles), dt: 0.016, friction: 0.85, boundsSize: boundsSize, numTypes: 7, cellSize: cellSize,
            sceneTriangleCount: 0, anchorCount: 0, boundsCenter: spawnCenter
        )
        
        guard let device = MTLCreateSystemDefaultDevice(), let commandQueue = device.makeCommandQueue(), let library = device.makeDefaultLibrary() else { return nil }
        self.device = device; self.commandQueue = commandQueue
        
        do {
            clearGridPipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "clearGrid")!)
            buildGridPipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "buildGrid")!)
            updatePipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "updateParticles")!)
        } catch { return nil }
        
        var rules = [Float](repeating: 0, count: 256)
        for i in 0..<256 { rules[i] = Float.random(in: -1.0...1.0) }
        rulesBuffer = device.makeBuffer(bytes: rules, length: MemoryLayout<Float>.stride * 256, options: .storageModeShared)
        
        let cellByteSize = MemoryLayout<Int32>.stride * 65
        gridBuffer = device.makeBuffer(length: cellByteSize * totalCells, options: .storageModePrivate)
        
        var initialParticles = [Particle]()
        initialParticles.reserveCapacity(totalParticles)
        let spawnHalfBounds: Float = 0.5
        for type in 0..<maxTypes {
            for _ in 0..<particlesPerType {
                let randomOffset = SIMD3<Float>.random(in: -spawnHalfBounds...spawnHalfBounds)
                initialParticles.append(Particle(
                    position: spawnCenter + randomOffset,
                    velocity: .zero, color: .zero, type: Int32(type)
                ))
            }
        }
        particleBuffer = device.makeBuffer(bytes: initialParticles, length: MemoryLayout<Particle>.stride * totalParticles, options: .storageModeShared)
        vertexBuffer = device.makeBuffer(length: totalParticles * 60 * 32, options: .storageModeShared)
    }
    
    func updateSceneMesh(anchor: MeshAnchor) {
        let geometry = anchor.geometry
        let transform = anchor.originFromAnchorTransform
        let verticesPointer = geometry.vertices.buffer.contents().advanced(by: geometry.vertices.offset)
        let facesPointer = geometry.faces.buffer.contents()
        let isUInt16 = geometry.faces.bytesPerIndex == 2
        let bytesPerPrimitive = geometry.faces.bytesPerIndex * 3
        var triangles = [SceneTriangle]()
        
        func getVertex(index: Int) -> SIMD3<Float> {
            let offset = index * geometry.vertices.stride
            let x = verticesPointer.advanced(by: offset).load(as: Float.self)
            let y = verticesPointer.advanced(by: offset + 4).load(as: Float.self)
            let z = verticesPointer.advanced(by: offset + 8).load(as: Float.self)
            return SIMD3<Float>(x, y, z)
        }
        
        for i in 0..<geometry.faces.count {
            let faceBytes = facesPointer.advanced(by: i * bytesPerPrimitive)
            let i0, i1, i2: Int
            if isUInt16 {
                let indexPtr = faceBytes.bindMemory(to: UInt16.self, capacity: 3)
                i0 = Int(indexPtr[0]); i1 = Int(indexPtr[1]); i2 = Int(indexPtr[2])
            } else {
                let indexPtr = faceBytes.bindMemory(to: UInt32.self, capacity: 3)
                i0 = Int(indexPtr[0]); i1 = Int(indexPtr[1]); i2 = Int(indexPtr[2])
            }
            
            let v0Local = getVertex(index: i0)
            let v1Local = getVertex(index: i1)
            let v2Local = getVertex(index: i2)
            
            let v0World4 = transform * SIMD4<Float>(v0Local.x, v0Local.y, v0Local.z, 1.0)
            let v1World4 = transform * SIMD4<Float>(v1Local.x, v1Local.y, v1Local.z, 1.0)
            let v2World4 = transform * SIMD4<Float>(v2Local.x, v2Local.y, v2Local.z, 1.0)
            
            let v0World = SIMD3<Float>(v0World4.x, v0World4.y, v0World4.z)
            let v1World = SIMD3<Float>(v1World4.x, v1World4.y, v1World4.z)
            let v2World = SIMD3<Float>(v2World4.x, v2World4.y, v2World4.z)
            
            let rawNormal = cross(v1World - v0World, v2World - v0World)
            if length(rawNormal) > 0.0001 {
                triangles.append(SceneTriangle(v0: v0World, v1: v1World, v2: v2World, normal: normalize(rawNormal)))
            }
        }
        
        meshAnchors[anchor.id] = triangles
        var allTriangles = [SceneTriangle]()
        var allBounds = [MeshAnchorBounds]()
        
        for (_, tris) in meshAnchors {
            if tris.isEmpty { continue }
            let chunkSize = 32
            for chunkStart in stride(from: 0, to: tris.count, by: chunkSize) {
                let chunkEnd = min(chunkStart + chunkSize, tris.count)
                var minX: Float = .greatestFiniteMagnitude, minY: Float = .greatestFiniteMagnitude, minZ: Float = .greatestFiniteMagnitude
                var maxX: Float = -.greatestFiniteMagnitude, maxY: Float = -.greatestFiniteMagnitude, maxZ: Float = -.greatestFiniteMagnitude
                for i in chunkStart..<chunkEnd {
                    let tri = tris[i]
                    minX = min(minX, tri.v0.x, tri.v1.x, tri.v2.x)
                    minY = min(minY, tri.v0.y, tri.v1.y, tri.v2.y)
                    minZ = min(minZ, tri.v0.z, tri.v1.z, tri.v2.z)
                    maxX = max(maxX, tri.v0.x, tri.v1.x, tri.v2.x)
                    maxY = max(maxY, tri.v0.y, tri.v1.y, tri.v2.y)
                    maxZ = max(maxZ, tri.v0.z, tri.v1.z, tri.v2.z)
                }
                let minB = SIMD3<Float>(minX, minY, minZ) - SIMD3<Float>(repeating: 0.02)
                let maxB = SIMD3<Float>(maxX, maxY, maxZ) + SIMD3<Float>(repeating: 0.02)
                
                allBounds.append(MeshAnchorBounds(minBounds: minB, maxBounds: maxB, startIndex: Int32(allTriangles.count), triangleCount: Int32(chunkEnd - chunkStart), pad1: 0, pad2: 0))
                for i in chunkStart..<chunkEnd { allTriangles.append(tris[i]) }
            }
        }
        
        sceneTriangleCount = Int32(allTriangles.count)
        anchorCount = Int32(allBounds.count)
        
        if sceneTriangleCount > 0 {
            let requiredSize = allTriangles.count * MemoryLayout<SceneTriangle>.stride
            if sceneMeshBuffer == nil || sceneMeshBuffer!.length < requiredSize {
                sceneMeshBuffer = device.makeBuffer(length: requiredSize * 2, options: .storageModeShared)
            }
            allTriangles.withUnsafeBytes { bufferPointer in
                sceneMeshBuffer?.contents().copyMemory(from: bufferPointer.baseAddress!, byteCount: requiredSize)
            }
            
            let boundsSize = allBounds.count * MemoryLayout<MeshAnchorBounds>.stride
            if anchorBoundsBuffer == nil || anchorBoundsBuffer!.length < boundsSize {
                anchorBoundsBuffer = device.makeBuffer(length: boundsSize * 2, options: .storageModeShared)
            }
            allBounds.withUnsafeBytes { bufferPointer in
                anchorBoundsBuffer?.contents().copyMemory(from: bufferPointer.baseAddress!, byteCount: boundsSize)
            }
        }
    }
    
    func stepSimulation(settings: SimulationSettings) {
            self.params.friction = settings.friction
            self.params.dt = settings.speed
            self.params.particleCount = Int32(settings.currentParticleCount)
            self.params.numTypes = Int32(settings.numTypes)
            
            self.params.sceneTriangleCount = sceneTriangleCount
            self.params.anchorCount = anchorCount
            
            self.params.prevLeftHandPos = prevLeftHandARKitPos
            self.params.prevRightHandPos = prevRightHandARKitPos
            self.params.leftHandPos = leftHandARKitPos
            self.params.rightHandPos = rightHandARKitPos
            
            prevLeftHandARKitPos = leftHandARKitPos
            prevRightHandARKitPos = rightHandARKitPos
            
            let rulesPointer = rulesBuffer.contents().bindMemory(to: Float.self, capacity: 256)
            for i in 0..<256 { rulesPointer[i] = settings.rules[i] }
            
            guard let commandBuffer = commandQueue.makeCommandBuffer(), let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
            
            encoder.setComputePipelineState(clearGridPipeline)
            encoder.setBuffer(gridBuffer, offset: 0, index: 0)
            encoder.dispatchThreads(MTLSizeMake(totalCells, 1, 1), threadsPerThreadgroup: MTLSizeMake(min(clearGridPipeline.maxTotalThreadsPerThreadgroup, totalCells), 1, 1))
            
            // 📍 永遠派發最大粒子數量 54000 給 GPU，不再從 CPU 端截斷
            let maxTotalParticles = 54000
            let particleGridSize = MTLSizeMake(maxTotalParticles, 1, 1)
            
            encoder.setComputePipelineState(buildGridPipeline)
            encoder.setBuffer(particleBuffer, offset: 0, index: 0)
            encoder.setBuffer(gridBuffer, offset: 0, index: 1)
            encoder.setBytes(&self.params, length: MemoryLayout<SimParams>.stride, index: 2)
            let buildThreadgroup = MTLSizeMake(min(buildGridPipeline.maxTotalThreadsPerThreadgroup, maxTotalParticles), 1, 1)
            encoder.dispatchThreads(particleGridSize, threadsPerThreadgroup: buildThreadgroup)
            
            encoder.setComputePipelineState(updatePipeline)
            encoder.setBuffer(particleBuffer, offset: 0, index: 0)
            encoder.setBuffer(gridBuffer, offset: 0, index: 1)
            encoder.setBytes(&self.params, length: MemoryLayout<SimParams>.stride, index: 2)
            encoder.setBuffer(rulesBuffer, offset: 0, index: 3)
            encoder.setBuffer(vertexBuffer, offset: 0, index: 4)
            
            if let sceneMeshBuffer = sceneMeshBuffer, let anchorBoundsBuffer = anchorBoundsBuffer, sceneTriangleCount > 0 {
                encoder.setBuffer(sceneMeshBuffer, offset: 0, index: 5)
                encoder.setBuffer(anchorBoundsBuffer, offset: 0, index: 6)
            } else {
                encoder.setBuffer(particleBuffer, offset: 0, index: 5)
                encoder.setBuffer(particleBuffer, offset: 0, index: 6)
            }
            
            let updateThreadgroup = MTLSizeMake(min(updatePipeline.maxTotalThreadsPerThreadgroup, maxTotalParticles), 1, 1)
            encoder.dispatchThreads(particleGridSize, threadsPerThreadgroup: updateThreadgroup)
            
            encoder.endEncoding()
            commandBuffer.commit()
        }
}
