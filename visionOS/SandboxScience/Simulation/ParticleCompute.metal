#include <metal_stdlib>
using namespace metal;

struct Particle {
    float3 position;
    float3 velocity;
    float3 color;
    int type;
};

struct SimParams {
    float3 leftHandPos;
    float3 rightHandPos;
    float3 prevLeftHandPos;
    float3 prevRightHandPos;
    int3 gridSize;
    int particleCount;
    float dt;
    float friction;
    float boundsSize;
    int numTypes;
    float cellSize;
    int sceneTriangleCount;
    int anchorCount;
    float3 boundsCenter;
};

struct RenderVertex {
    float3 position;
    float3 normal;
};

struct SceneTriangle {
    float3 v0;
    float3 v1;
    float3 v2;
    float3 normal;
};

struct MeshAnchorBounds {
    float3 minBounds;
    float3 maxBounds;
    int startIndex;
    int triangleCount;
    int pad1;
    int pad2;
};

float distToSegment(float3 p, float3 a, float3 b, thread float3& closestPoint) {
    float3 ab = b - a;
    float t = dot(p - a, ab) / max(dot(ab, ab), 1e-5f);
    t = clamp(t, 0.0f, 1.0f);
    closestPoint = a + t * ab;
    return length(p - closestPoint);
}

kernel void clearGrid(device atomic_int* grid [[buffer(0)]], uint id [[thread_position_in_grid]]) {
    atomic_store_explicit(&grid[id * 65], 0, memory_order_relaxed);
}

kernel void buildGrid(device const Particle* particles [[buffer(0)]], device atomic_int* grid [[buffer(1)]], constant SimParams& params [[buffer(2)]], uint id [[thread_position_in_grid]]) {
    if (id >= (uint)params.particleCount) return;
    
    float3 pShifted = particles[id].position - params.boundsCenter + float3(params.boundsSize * 0.5f);
    int3 cell3D = clamp(int3(pShifted / params.cellSize), 0, params.gridSize - 1);
    int cellIdx = (cell3D.z * params.gridSize.y + cell3D.y) * params.gridSize.x + cell3D.x;
    int count = atomic_fetch_add_explicit(&grid[cellIdx * 65], 1, memory_order_relaxed);
    if (count < 64) atomic_store_explicit(&grid[cellIdx * 65 + 1 + count], (int)id, memory_order_relaxed);
}

kernel void updateParticles(device Particle* particles [[buffer(0)]],
                            device const atomic_int* grid [[buffer(1)]],
                            constant SimParams& params [[buffer(2)]],
                            device const float* rules [[buffer(3)]],
                            device RenderVertex* renderVertices [[buffer(4)]],
                            device const SceneTriangle* sceneTriangles [[buffer(5)]],
                            device const MeshAnchorBounds* anchorBounds [[buffer(6)]],
                            uint id [[thread_position_in_grid]]) {
    
    if (id >= (uint)params.particleCount) return;
    Particle p = particles[id];
    
    float3 force = float3(0);
    float rMax = 0.2f;
    
    float3 pShifted = p.position - params.boundsCenter + float3(params.boundsSize * 0.5f);
    int3 cell3D = int3(pShifted / params.cellSize);
    
    for (int z = -1; z <= 1; z++) {
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                int3 neighbor = cell3D + int3(x, y, z);
                if (neighbor.x >= 0 && neighbor.x < params.gridSize.x &&
                    neighbor.y >= 0 && neighbor.y < params.gridSize.y &&
                    neighbor.z >= 0 && neighbor.z < params.gridSize.z) {
                    
                    int cellIdx = (neighbor.z * params.gridSize.y + neighbor.y) * params.gridSize.x + neighbor.x;
                    int count = min(atomic_load_explicit(&grid[cellIdx * 65], memory_order_relaxed), 64);
                    
                    for (int i = 0; i < count; i++) {
                        int otherId = atomic_load_explicit(&grid[cellIdx * 65 + 1 + i], memory_order_relaxed);
                        if (otherId == (int)id) continue;
                        
                        Particle other = particles[otherId];
                        float3 d = p.position - other.position;
                        float dist = length(d);
                        
                        if (dist > 0.0f && dist < rMax) {
                            float3 dir = d / dist;
                            
                            int safeNumTypes = max(params.numTypes, 1);
                            int effectiveTypeA = p.type;
                            if (effectiveTypeA >= safeNumTypes) effectiveTypeA = effectiveTypeA % safeNumTypes;
                            
                            int effectiveTypeB = other.type;
                            if (effectiveTypeB >= safeNumTypes) effectiveTypeB = effectiveTypeB % safeNumTypes;
                            
                            float rule = rules[effectiveTypeA * 16 + effectiveTypeB];
                            
                            float f = (dist < 0.02f) ? ((0.02f - dist) / 0.02f * 2.0f) : (rule * (1.0f - abs(dist - 0.11f) / 0.09f) * 0.1f);
                            force += dir * f;
                        }
                    }
                }
            }
        }
    }
    
    p.velocity = (p.velocity + force * params.dt) * params.friction;
    
    float touchRadius = 0.04f;
    float safeDt = max(params.dt, 1e-5f);
    
    float3 handVelL = (params.leftHandPos - params.prevLeftHandPos) / safeDt;
    if (length(handVelL) > 3.0f) handVelL = normalize(handVelL) * 3.0f;
    
    float3 closestL;
    float distL = distToSegment(p.position, params.prevLeftHandPos, params.leftHandPos, closestL);
    if (distL > 0.0f && distL < touchRadius) {
        float3 dir = normalize(p.position - closestL);
        float penetration = touchRadius - distL;
        float3 pushOutVel = dir * (penetration / safeDt);
        p.velocity = pushOutVel * 0.8f + handVelL * 0.8f;
    }
    
    float3 handVelR = (params.rightHandPos - params.prevRightHandPos) / safeDt;
    if (length(handVelR) > 3.0f) handVelR = normalize(handVelR) * 3.0f;
    
    float3 closestR;
    float distR = distToSegment(p.position, params.prevRightHandPos, params.rightHandPos, closestR);
    if (distR > 0.0f && distR < touchRadius) {
        float3 dir = normalize(p.position - closestR);
        float penetration = touchRadius - distR;
        float3 pushOutVel = dir * (penetration / safeDt);
        p.velocity = pushOutVel * 0.8f + handVelR * 0.8f;
    }
    
    float maxSpeed = 10.0f;
    if (length(p.velocity) > maxSpeed) p.velocity = normalize(p.velocity) * maxSpeed;
    
    float3 nextPos = p.position + p.velocity * params.dt;
    
    float halfB = params.boundsSize * 0.5f;
    float3 minB = params.boundsCenter - halfB;
    float3 maxB = params.boundsCenter + halfB;
    if (nextPos.x > maxB.x) { p.velocity.x *= -1; nextPos.x = clamp(nextPos.x, minB.x, maxB.x); }
    if (nextPos.x < minB.x) { p.velocity.x *= -1; nextPos.x = clamp(nextPos.x, minB.x, maxB.x); }
    if (nextPos.y > maxB.y) { p.velocity.y *= -1; nextPos.y = clamp(nextPos.y, minB.y, maxB.y); }
    if (nextPos.y < minB.y) { p.velocity.y *= -1; nextPos.y = clamp(nextPos.y, minB.y, maxB.y); }
    if (nextPos.z > maxB.z) { p.velocity.z *= -1; nextPos.z = clamp(nextPos.z, minB.z, maxB.z); }
    if (nextPos.z < minB.z) { p.velocity.z *= -1; nextPos.z = clamp(nextPos.z, minB.z, maxB.z); }
    
    float particleRadius = 0.005f;
    
    if (params.anchorCount > 0) {
        for (int a = 0; a < params.anchorCount; a++) {
            MeshAnchorBounds bounds = anchorBounds[a];
            float margin = 0.05f;
            
            if (nextPos.x < bounds.minBounds.x - margin || nextPos.x > bounds.maxBounds.x + margin ||
                nextPos.y < bounds.minBounds.y - margin || nextPos.y > bounds.maxBounds.y + margin ||
                nextPos.z < bounds.minBounds.z - margin || nextPos.z > bounds.maxBounds.z + margin) {
                continue;
            }
            
            for (int i = 0; i < bounds.triangleCount; i++) {
                SceneTriangle tri = sceneTriangles[bounds.startIndex + i];
                
                float3 triMin = min(min(tri.v0, tri.v1), tri.v2) - margin;
                float3 triMax = max(max(tri.v0, tri.v1), tri.v2) + margin;
                if (nextPos.x < triMin.x || nextPos.x > triMax.x ||
                    nextPos.y < triMin.y || nextPos.y > triMax.y ||
                    nextPos.z < triMin.z || nextPos.z > triMax.z) {
                    continue;
                }
                
                float distToPlane = dot(nextPos - tri.v0, tri.normal);
                float prevDist = dot(p.position - tri.v0, tri.normal);
                
                if ((prevDist * distToPlane <= 0.0f) || abs(distToPlane) < particleRadius) {
                    float3 hitPoint;
                    if (prevDist * distToPlane <= 0.0f) {
                        float t = prevDist / (prevDist - distToPlane);
                        hitPoint = p.position + (nextPos - p.position) * t;
                    } else {
                        hitPoint = p.position;
                    }
                    
                    float3 c0 = hitPoint - tri.v0;
                    float3 c1 = hitPoint - tri.v1;
                    float3 c2 = hitPoint - tri.v2;
                    
                    float d0 = dot(tri.normal, cross(tri.v1 - tri.v0, c0));
                    float d1 = dot(tri.normal, cross(tri.v2 - tri.v1, c1));
                    float d2 = dot(tri.normal, cross(tri.v0 - tri.v2, c2));
                    
                    float eps = -1e-4f;
                    if ((d0 >= eps && d1 >= eps && d2 >= eps) || (d0 <= -eps && d1 <= -eps && d2 <= -eps)) {
                        float3 hitNormal = (prevDist > 0) ? tri.normal : -tri.normal;
                        
                        if (dot(p.velocity, hitNormal) < 0) {
                            p.velocity = reflect(p.velocity, hitNormal) * 0.6f;
                        }
                        
                        nextPos = hitPoint + hitNormal * particleRadius;
                        break;
                    }
                }
            }
        }
    }
    
    p.position = nextPos;
    particles[id] = p;
    
    const float t = 1.61803398875f;
    const float3 v[12] = {
        float3(-1,  t,  0), float3( 1,  t,  0), float3(-1, -t,  0), float3( 1, -t,  0),
        float3( 0, -1,  t), float3( 0,  1,  t), float3( 0, -1, -t), float3( 0,  1, -t),
        float3( t,  0, -1), float3( t,  0,  1), float3(-t,  0, -1), float3(-t,  0,  1)
    };
    const int indices[60] = {
        0,11,5, 0,5,1, 0,1,7, 0,7,10, 0,10,11, 1,5,9, 5,11,4, 11,10,2, 10,7,6, 7,1,8,
        3,9,4, 3,4,2, 3,2,6, 3,6,8, 3,8,9, 4,9,5, 2,4,11, 6,2,10, 8,6,7, 9,8,1
    };
    
    int vertexOffset = id * 60;
    float renderRadius = 0.005f;
    
    for(int i = 0; i < 20; i++) {
        float3 p0 = normalize(v[indices[i*3]]) * renderRadius;
        float3 p1 = normalize(v[indices[i*3+1]]) * renderRadius;
        float3 p2 = normalize(v[indices[i*3+2]]) * renderRadius;
        float3 normal = normalize(cross(p1 - p0, p2 - p0));
        
        renderVertices[vertexOffset + i*3].position = p.position + p0;
        renderVertices[vertexOffset + i*3].normal = normal;
        renderVertices[vertexOffset + i*3 + 1].position = p.position + p1;
        renderVertices[vertexOffset + i*3 + 1].normal = normal;
        renderVertices[vertexOffset + i*3 + 2].position = p.position + p2;
        renderVertices[vertexOffset + i*3 + 2].normal = normal;
    }
}
