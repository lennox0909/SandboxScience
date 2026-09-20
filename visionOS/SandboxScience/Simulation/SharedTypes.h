#ifndef SharedTypes_h
#define SharedTypes_h
#include <simd/simd.h>

typedef struct {
    vector_float3 position;
    vector_float3 velocity;
    vector_float4 color;
    int type;
} Particle;

typedef struct {
    vector_float3 leftHandPos;
    vector_float3 rightHandPos;
    vector_int3 gridSize;
    int particleCount;
    float dt;
    float friction;
    float boundsSize;
    int numTypes;
    float cellSize;
} SimParams;

// 📍 為了讓 RealityKit 算得出立體陰影，加入 normal 法線
typedef struct {
    vector_float3 position; // offset 0
    vector_float3 normal;   // offset 16
} RenderVertex;

#endif
