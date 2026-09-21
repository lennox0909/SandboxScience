import SwiftUI
import RealityKit
import ARKit

struct ImmersiveView: View {
    var settings: SimulationSettings

    @State private var simulator: ParticleSimulator?
    @State private var particleMesh: LowLevelMesh?
    @State private var updateSubscription: EventSubscription?
    @State private var session = ARKitSession()
    
    // 📍 鎖定在真實物理世界地板的絕對錨點
    @State private var arkitOriginAnchor = AnchorEntity(world: matrix_identity_float4x4)
    
    var body: some View {
        RealityView { content in
            content.add(arkitOriginAnchor)
            
            if simulator == nil { simulator = ParticleSimulator(boundsSize: 5.0) }
            guard let simulator = simulator else { return }
            
            do {
                let (entity, mesh) = try createParticleMesh()
                self.particleMesh = mesh
                
                let colors: [UIColor] = [.systemRed, .systemGreen, .systemBlue, .systemYellow, .systemPurple, .systemCyan]
                var materials = [SimpleMaterial]()
                for color in colors { materials.append(SimpleMaterial(color: color, isMetallic: false)) }
                
                entity.components.set(ModelComponent(mesh: entity.model!.mesh, materials: materials))
                
                // 📍 終極修復：不再設定 entity.position！
                // 直接將粒子設為物理原點的子物件，讓粒子的座標系 100% 等於真實宇宙座標！
                arkitOriginAnchor.addChild(entity)
                
                updateSubscription = content.subscribe(to: SceneEvents.Update.self) { _ in
                    guard let mesh = self.particleMesh else { return }
                    
                    simulator.stepSimulation(settings: settings)
                    
                    mesh.withUnsafeMutableBytes(bufferIndex: 0) { meshBuffer in
                        let sourcePointer = simulator.vertexBuffer.contents()
                        meshBuffer.copyMemory(from: UnsafeRawBufferPointer(start: sourcePointer, count: meshBuffer.count))
                    }
                }
            } catch { print("Mesh Error: \(error)") }
        }
        .task {
            guard HandTrackingProvider.isSupported, SceneReconstructionProvider.isSupported else { return }
            let handTracking = HandTrackingProvider()
            let sceneReconstruction = SceneReconstructionProvider()
            
            do {
                let authStatus = await session.requestAuthorization(for: [.handTracking, .worldSensing])
                if authStatus[.handTracking] != .allowed || authStatus[.worldSensing] != .allowed { return }
                
                try await session.run([handTracking, sceneReconstruction])
                
                Task {
                    for await update in handTracking.anchorUpdates {
                        let handAnchor = update.anchor
                        guard handAnchor.isTracked else { continue }
                        // 現在雙手抓到的 ARKit 絕對座標，直接就能拿來用！
                        let arkitPos = SIMD3<Float>(handAnchor.originFromAnchorTransform.columns.3.x, handAnchor.originFromAnchorTransform.columns.3.y, handAnchor.originFromAnchorTransform.columns.3.z)
                        if handAnchor.chirality == .left { simulator?.leftHandARKitPos = arkitPos }
                        else { simulator?.rightHandARKitPos = arkitPos }
                    }
                }
                
                Task {
                    for await update in sceneReconstruction.anchorUpdates {
                        await MainActor.run { simulator?.updateSceneMesh(anchor: update.anchor) }
                    }
                }
            } catch { print("ARKit Session Error: \(error)") }
        }
    }
}

func createParticleMesh() throws -> (ModelEntity, LowLevelMesh) {
    let particlesPerType = 9000
    let numTypes = 6
    let vertexCountPerType = particlesPerType * 60
    let totalVertexCount = vertexCountPerType * numTypes
    var descriptor = LowLevelMesh.Descriptor()
    descriptor.vertexCapacity = totalVertexCount; descriptor.indexCapacity = totalVertexCount
    descriptor.vertexAttributes = [
        LowLevelMesh.Attribute(semantic: .position, format: .float3, offset: 0),
        LowLevelMesh.Attribute(semantic: .normal, format: .float3, offset: 16)
    ]
    descriptor.vertexLayouts = [LowLevelMesh.Layout(bufferIndex: 0, bufferStride: 32)]
    let mesh = try LowLevelMesh(descriptor: descriptor)
    mesh.withUnsafeMutableIndices { buffer in
        let typedBuffer = buffer.bindMemory(to: UInt32.self)
        for i in 0..<totalVertexCount { typedBuffer[i] = UInt32(i) }
    }
    var parts = [LowLevelMesh.Part]()
    // 放寬渲染邊界，防止粒子稍微飛遠就消失
    let meshBounds = BoundingBox(min: SIMD3<Float>(-5, -5, -5), max: SIMD3<Float>(5, 5, 5))
    for i in 0..<numTypes {
        parts.append(LowLevelMesh.Part(indexOffset: i * vertexCountPerType, indexCount: vertexCountPerType, topology: .triangle, materialIndex: i, bounds: meshBounds))
    }
    mesh.parts.replaceAll(parts)
    return (ModelEntity(mesh: try MeshResource(from: mesh)), mesh)
}
