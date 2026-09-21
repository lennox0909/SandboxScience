# Particle Life: visionOS 空間運算版 🌌

本專案是將經典的「Particle Life (人工生命粒子模擬)」成功移植至 Apple Vision Pro (visionOS) 的重大效能突破版本。透過整合 Apple 的 GPU 運算與沉浸式空間，我們成功讓 5.4 萬顆粒子在實體環境中流暢互動。

## 🚀 核心技術與亮點

*   **極致效能 (5.4 萬顆粒子)**：跳脫傳統 $O(N^2)$ 的效能瓶頸，實作 **Spatial Hashing (空間網格)** 演算法。透過 27 個鄰近網格搜尋與 `max_per_cell = 64` 的限制，在 M5 晶片上達成滿幀率 (60+ FPS) 完美運行。
*   **GPU 幾何展開與光影烘焙**：捨棄消耗 CPU 資源的實體生成，直接在 `ParticleCompute.metal` 中以幾何著色器 (Geometry Expansion) 將單一粒子展開為 **60 頂點的二十面體 (Icosahedron)**，生成總計超過 300 萬個頂點的精緻 3D 圓球。
*   **物理材質與法線支援**：自訂 `RenderVertex` 結構 (32 Bytes)，將粒子位置與 3D 表面法線 (Normal) 傳遞給 RealityKit 的 `SimpleMaterial`，呈現出帶有環境光澤與立體陰影的彩色實體質感。
*   **ARKit 雙手互動**：透過 `HandTrackingProvider` 追蹤雙手的三維空間座標，實作排斥力場 (Repulsion Field) 與邊界環境阻尼控制，讓使用者能用雙手直接撥開粒子群。

---

## 📂 專案目錄結構與 Target Membership

在 Xcode 中新增檔案時，請確保右側 Inspector 面板的 `Target Membership` 設定正確，否則將導致編譯失敗或找不到資源：

```text
SandboxScience/
├── visionOS/
│   ├── SandboxScience/
│   │   ├── SharedTypes.h           # Target: 不需勾選 (C 標頭檔，由 Metal 與 Swift 橋接引用)
│   │   ├── ParticleCompute.metal   # Target: ✅ 勾選 SandboxScience (確保編譯入 GPU default.metallib)
│   │   ├── ParticleSimulator.swift # Target: ✅ 勾選 SandboxScience
│   │   ├── ImmersiveView.swift     # Target: ✅ 勾選 SandboxScience
│   │   └── Info.plist              # Target: 不需勾選 (於 Target 的 Build Settings 中綁定)
│   └── README.md                   # Target: 不需勾選 (說明文件)
└── (其他主專案檔案...)
```

---

## ⚙️ 關鍵專案設定 (Xcode Build Settings & Info.plist)

為了確保專案能順利編譯並啟動沉浸式空間，請確認 Xcode 中的以下設定：

### 1. Build Settings
在專案的 `Build Settings` 標籤頁中，確認 Metal 編譯器版本：
*   **Metal Language Revision:** `Metal 4.0`

### 2. Info.plist (Application Scene Manifest)
展開 `Information Property List`，確保 `Application Scene Manifest` 包含以下混合實境 (Mixed Reality) 的必要配置：

*   **Enable Multiple Scenes:** `YES`
*   **Preferred Default Scene Session Role:** `Window Application Session Role`
*   **Scene Configuration**:
    *   新增 `Immersive Space Application Session Role` (Array)
    *   在該 Array 下建立 `Item 0` (Dictionary)
    *   設定 **`Initial Immersion Style`** 為 **`Mixed Immersion`**

---

## 🛠️ 未來發展與實驗方向

本架構擁有極高的效能餘裕，未來可進一步探索：
1. 將粒子數量推升至 10 萬顆以上的極限壓力測試。
2. 結合 `SceneReconstructionProvider` 讓粒子能與真實世界的牆壁或家具發生物理碰撞。
3. 加入更多物種 (Types) 與動態調整引力/斥力參數的 UI 控制面板。