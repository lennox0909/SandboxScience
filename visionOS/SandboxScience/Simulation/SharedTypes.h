#ifndef SharedTypes_h
#define SharedTypes_h

#include <simd/simd.h>

struct Particle {
    vector_float3 position;
    vector_float3 velocity;
    vector_float3 color;
    int type;
};

struct SimParams {
    vector_float3 leftHandPos;
    vector_float3 rightHandPos;
    vector_float3 prevLeftHandPos;   // 📍 左手前一幀座標
    vector_float3 prevRightHandPos;  // 📍 右手前一幀座標
    vector_int3 gridSize;
    int particleCount;
    float dt;
    float friction;
    float boundsSize;
    int numTypes;                    // 📍 粒子種類數量
    float cellSize;
    int sceneTriangleCount;
    int anchorCount;
    vector_float3 boundsCenter;
};

struct RenderVertex {
    vector_float3 position;
    vector_float3 normal;
};

struct SceneTriangle {
    vector_float3 v0;
    vector_float3 v1;
    vector_float3 v2;
    vector_float3 normal;
};

struct MeshAnchorBounds {
    vector_float3 minBounds;
    vector_float3 maxBounds;
    int startIndex;
    int triangleCount;
    int pad1;
    int pad2;
};

#endif /* SharedTypes_h */
