import SwiftUI
import RealityKit
import ARKit

struct ImmersiveView: View {
    @State private var simulator = ParticleSimulator(boundsSize: 1.5)
    @State private var particleMesh: LowLevelMesh?
    @State private var updateSubscription: EventSubscription?
    @State private var session = ARKitSession()
    let entityPosition = SIMD3<Float>(0, 1.2, -0.6)
    
    var body: some View {
        RealityView { content in
            guard let simulator = simulator else { return }
            do {
                let (entity, mesh) = try createParticleMesh()
                self.particleMesh = mesh
                
                // 🎨 拋棄過曝白光的 Unlit，改用具有光澤與立體陰影的 SimpleMaterial
                let colors: [UIColor] = [.systemRed, .systemGreen, .systemBlue, .systemYellow, .systemPurple, .systemCyan]
                var materials = [SimpleMaterial]()
                for color in colors {
                    // isMetallic: false 讓它們看起來像溫潤的彩色塑料/橡膠球
                    materials.append(SimpleMaterial(color: color, isMetallic: false))
                }
                
                entity.components.set(ModelComponent(mesh: entity.model!.mesh, materials: materials))
                entity.position = entityPosition
                content.add(entity)
                
                updateSubscription = content.subscribe(to: SceneEvents.Update.self) { _ in
                    guard let mesh = self.particleMesh else { return }
                    simulator.stepSimulation()
                    mesh.withUnsafeMutableBytes(bufferIndex: 0) { meshBuffer in
                        let sourcePointer = simulator.vertexBuffer.contents()
                        meshBuffer.copyMemory(from: UnsafeRawBufferPointer(start: sourcePointer, count: meshBuffer.count))
                    }
                }
            } catch { print("Mesh Error: \(error)") }
        }
        .task {
            guard HandTrackingProvider.isSupported else { return }
            let handTracking = HandTrackingProvider()
            do {
                let authStatus = await session.requestAuthorization(for: [.handTracking])
                if authStatus[.handTracking] != .allowed { return }
                try await session.run([handTracking])
                for await update in handTracking.anchorUpdates {
                    let handAnchor = update.anchor
                    guard handAnchor.isTracked else { continue }
                    let localPosition = SIMD3<Float>(handAnchor.originFromAnchorTransform.columns.3.x, handAnchor.originFromAnchorTransform.columns.3.y, handAnchor.originFromAnchorTransform.columns.3.z) - entityPosition
                    if handAnchor.chirality == .left { simulator?.params.leftHandPos = localPosition }
                    else { simulator?.params.rightHandPos = localPosition }
                }
            } catch {}
        }
    }
}

func createParticleMesh() throws -> (ModelEntity, LowLevelMesh) {
    let particlesPerType = 9000
    let numTypes = 6
    let vertexCountPerType = particlesPerType * 60
    let totalVertexCount = vertexCountPerType * numTypes
    
    var descriptor = LowLevelMesh.Descriptor()
    descriptor.vertexCapacity = totalVertexCount
    descriptor.indexCapacity = totalVertexCount
    
    // 📍 關鍵：提供法線 (normal) 給 RealityKit 的打光系統
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
    let meshBounds = BoundingBox(min: SIMD3<Float>(-1.5, -1.5, -1.5), max: SIMD3<Float>(1.5, 1.5, 1.5))
    
    for i in 0..<numTypes {
        parts.append(LowLevelMesh.Part(
            indexOffset: i * vertexCountPerType,
            indexCount: vertexCountPerType,
            topology: .triangle,
            materialIndex: i,
            bounds: meshBounds
        ))
    }
    mesh.parts.replaceAll(parts)
    
    return (ModelEntity(mesh: try MeshResource(from: mesh)), mesh)
}
