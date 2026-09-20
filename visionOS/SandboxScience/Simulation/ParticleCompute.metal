#include <metal_stdlib>
#include "SharedTypes.h"
using namespace metal;

#define MAX_PER_CELL 64
struct Cell { atomic_int count; int indices[MAX_PER_CELL]; };

inline int3 getGridCoord(float3 pos, float boundsSize, float cellSize, int3 gridSize) {
    float3 normalizedPos = pos + (boundsSize / 2.0);
    return clamp(int3(normalizedPos / cellSize), int3(0), gridSize - int3(1));
}
inline int getIndexFromCoord(int3 coord, int3 gridSize) {
    return coord.x + coord.y * gridSize.x + coord.z * gridSize.x * gridSize.y;
}

kernel void clearGrid(device Cell *grid [[buffer(0)]], uint id [[thread_position_in_grid]]) {
    atomic_store_explicit(&grid[id].count, 0, memory_order_relaxed);
}

kernel void buildGrid(device Particle *particles [[buffer(0)]], device Cell *grid [[buffer(1)]], constant SimParams &params [[buffer(2)]], uint id [[thread_position_in_grid]]) {
    if (id >= (uint)params.particleCount) return;
    int3 coord = getGridCoord(particles[id].position, params.boundsSize, params.cellSize, params.gridSize);
    int gridIdx = getIndexFromCoord(coord, params.gridSize);
    int index = atomic_fetch_add_explicit(&grid[gridIdx].count, 1, memory_order_relaxed);
    if (index < MAX_PER_CELL) grid[gridIdx].indices[index] = id;
}

kernel void updateParticles(device Particle *particles [[buffer(0)]], device Cell *grid [[buffer(1)]], constant SimParams &params [[buffer(2)]], constant float *rules [[buffer(3)]], device RenderVertex *renderVertices [[buffer(4)]], uint id [[thread_position_in_grid]]) {
    if (id >= (uint)params.particleCount) return;
    Particle p = particles[id];
    float3 totalForce = float3(0);
    int3 cellCoord = getGridCoord(p.position, params.boundsSize, params.cellSize, params.gridSize);
    
    for (int z = -1; z <= 1; z++) {
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                int3 neighborCoord = cellCoord + int3(x, y, z);
                if (any(neighborCoord < 0) || any(neighborCoord >= params.gridSize)) continue;
                int neighborIdx = getIndexFromCoord(neighborCoord, params.gridSize);
                int count = min(atomic_load_explicit(&grid[neighborIdx].count, memory_order_relaxed), MAX_PER_CELL);
                for (int i = 0; i < count; i++) {
                    int otherId = grid[neighborIdx].indices[i];
                    if (otherId == (int)id) continue;
                    Particle other = particles[otherId];
                    float3 diff = other.position - p.position;
                    float dist = length(diff);
                    if (dist > 0.001 && dist < params.cellSize) {
                        float ruleValue = rules[p.type * params.numTypes + other.type];
                        float force = (dist < 0.02) ? -0.5 * (1.0 - dist / 0.02) : ruleValue * (1.0 - (dist - 0.02) / (params.cellSize - 0.02)) * 0.005;
                        totalForce += normalize(diff) * force;
                    }
                }
            }
        }
    }
    
    float3 toLeftHand = params.leftHandPos - p.position;
    if (length(toLeftHand) < 0.6) totalForce -= normalize(toLeftHand) * (0.6 - length(toLeftHand)) * 3.0;
    float3 toRightHand = params.rightHandPos - p.position;
    if (length(toRightHand) < 0.6) totalForce -= normalize(toRightHand) * (0.6 - length(toRightHand)) * 3.0;
    
    p.velocity += totalForce;
    p.velocity *= params.friction;
    p.position += p.velocity * params.dt;
    
    float halfBounds = params.boundsSize / 2.0;
    if (abs(p.position.x) > halfBounds) { p.position.x = sign(p.position.x) * halfBounds; p.velocity.x *= -0.5; }
    if (abs(p.position.y) > halfBounds) { p.position.y = sign(p.position.y) * halfBounds; p.velocity.y *= -0.5; }
    if (abs(p.position.z) > halfBounds) { p.position.z = sign(p.position.z) * halfBounds; p.velocity.z *= -0.5; }
    
    particles[id] = p;
    
    // 🎨 生成 60 頂點的二十面體圓球，並計算表面法線
    float r = 0.003;
    float a = 0.5257311121191336 * r;
    float b = 0.8506508083520399 * r;

    float3 v[12] = {
        float3(-a,  b,  0), float3( a,  b,  0), float3(-a, -b,  0), float3( a, -b,  0),
        float3( 0, -a,  b), float3( 0,  a,  b), float3( 0, -a, -b), float3( 0,  a, -b),
        float3( b,  0, -a), float3( b,  0,  a), float3(-b,  0, -a), float3(-b,  0,  a)
    };

    int indices[60] = {
        0,11,5,  0,5,1,   0,1,7,   0,7,10,  0,10,11,
        1,5,9,   5,11,4,  11,10,2, 10,7,6,  7,1,8,
        3,9,4,   3,4,2,   3,2,6,   3,6,8,   3,8,9,
        4,9,5,   2,4,11,  6,2,10,  8,6,7,   9,8,1
    };

    int baseIdx = id * 60;
    for (int i = 0; i < 60; i++) {
        float3 localPos = v[indices[i]];
        renderVertices[baseIdx + i].position = p.position + localPos;
        // 📍 圓球的法線非常簡單，就是從中心指向頂點的向量
        renderVertices[baseIdx + i].normal = normalize(localPos);
    }
}
