import SwiftUI
import RealityKit
import ARKit

struct ImmersiveView: View {
    var settings: SimulationSettings
    @Environment(AppModel.self) var appModel

    @State private var simulator: ParticleSimulator?
    @State private var particleMesh: LowLevelMesh?
    @State private var updateSubscription: EventSubscription?
    @State private var session = ARKitSession()
    
    @State private var arkitOriginAnchor = AnchorEntity(world: matrix_identity_float4x4)
    @State private var rightWristAnchor = Entity()
    
    var body: some View {
        RealityView { content, attachments in
            content.add(arkitOriginAnchor)
            arkitOriginAnchor.addChild(rightWristAnchor)
            
            if let menuEntity = attachments.entity(for: "wristMenu") {
                menuEntity.position = SIMD3<Float>(0, 0.12, 0.03)
                menuEntity.transform.rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(1, 0, 0))
                menuEntity.scale = SIMD3<Float>(0.5, 0.5, 0.5)
                rightWristAnchor.addChild(menuEntity)
            }
            
            if simulator == nil { simulator = ParticleSimulator(boundsSize: 5.0) }
            guard let simulator = simulator else { return }
            
            do {
                let (entity, mesh) = try createParticleMesh()
                self.particleMesh = mesh
                
                let colors: [UIColor] = [
                    .systemRed, .systemGreen, .systemBlue, .systemYellow, .systemPurple, .systemCyan,
                    .systemOrange, .systemPink, .brown, .lightGray, .darkGray, .black,
                    .magenta, .systemTeal, .systemIndigo, .white
                ]
                var materials = [SimpleMaterial]()
                for color in colors { materials.append(SimpleMaterial(color: color, isMetallic: false)) }
                
                entity.components.set(ModelComponent(mesh: entity.model!.mesh, materials: materials))
                arkitOriginAnchor.addChild(entity)
                
                updateSubscription = content.subscribe(to: SceneEvents.Update.self) { _ in
                    guard let mesh = self.particleMesh else { return }
                    
                    simulator.stepSimulation(settings: settings)
                    
                    mesh.withUnsafeMutableBytes(bufferIndex: 0) { meshBuffer in
                        let sourcePointer = simulator.vertexBuffer.contents()
                        let activeVertexBytes = Int(settings.currentParticleCount) * 60 * 32
                        meshBuffer.copyMemory(from: UnsafeRawBufferPointer(start: sourcePointer, count: activeVertexBytes))
                    }
                }
            } catch { print("Mesh Error: \(error)") }
            
        } attachments: {
            Attachment(id: "wristMenu") {
                ControlPanelView(settings: settings)
            }
        }
        .onAppear {
            appModel.immersiveSpaceState = .open
        }
        .onDisappear {
            appModel.immersiveSpaceState = .closed
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
                        
                        let arkitPos = SIMD3<Float>(handAnchor.originFromAnchorTransform.columns.3.x, handAnchor.originFromAnchorTransform.columns.3.y, handAnchor.originFromAnchorTransform.columns.3.z)
                        
                        if handAnchor.chirality == .left {
                            simulator?.leftHandARKitPos = arkitPos
                        } else {
                            simulator?.rightHandARKitPos = arkitPos
                            
                            if let wrist = handAnchor.handSkeleton?.joint(.wrist), wrist.isTracked {
                                let wristTransform = matrix_multiply(handAnchor.originFromAnchorTransform, wrist.anchorFromJointTransform)
                                await MainActor.run {
                                    rightWristAnchor.transform = Transform(matrix: wristTransform)
                                }
                            }
                        }
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
    let maxTypes = 16
    let particlesPerType = 3375
    let vertexCountPerType = particlesPerType * 60
    let totalVertexCount = vertexCountPerType * maxTypes
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
    let meshBounds = BoundingBox(min: SIMD3<Float>(-5, -5, -5), max: SIMD3<Float>(5, 5, 5))
    for i in 0..<maxTypes {
        parts.append(LowLevelMesh.Part(indexOffset: i * vertexCountPerType, indexCount: vertexCountPerType, topology: .triangle, materialIndex: i, bounds: meshBounds))
    }
    mesh.parts.replaceAll(parts)
    return (ModelEntity(mesh: try MeshResource(from: mesh)), mesh)
}
