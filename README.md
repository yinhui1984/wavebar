# Wavebar - macOS 原生音频频谱可视化器

Wavebar 是一款基于 Swift 和 SwiftUI 的 macOS 原生音频频谱可视化 GUI 应用。它通过 CoreAudio 与 AVAudioEngine 实时捕获系统音频，使用 Accelerate/vDSP 框架进行 FFT 频谱分析，采用双线程环形缓冲区架构，并在 SwiftUI Canvas 上利用 CADisplayLink 与屏幕硬件刷新率（支持 ProMotion 120Hz/144Hz）同步渲染。应用支持玻璃磨砂视觉风格（Glassmorphism）、窗口高度自适应布局和桌面融入模式。

## 预览

![Wavebar 主界面](docs/images/wavebar-main.png)

![Wavebar 设置面板](docs/images/wavebar-settings.png)

![screenshot3](docs/images/screenshot_3.png)

---

## 📖 目录
1. [🔌 环境准备与音频路由 (BlackHole 设置)](#-环境准备与音频路由-blackhole-设置)
2. [🎛️ 操作手册 (User Manual)](#️-操作手册-user-manual)
   - [悬浮控制栏与设置参数](#1-悬浮控制栏与设置参数)
   - [自适应紧凑布局 (Compact Layout)](#2-自适应紧凑布局-compact-layout)
   - [桌面融入模式 (Desktop Blend Mode)](#3-桌面融入模式-desktop-blend-mode)
   - [配置持久化与窗口恢复](#4-配置持久化与窗口恢复)
3. [💻 二次开发手册 (Developer Guide)](#-二次开发手册-developer-guide)
   - [项目文件结构](#项目文件结构)
   - [核心架构与数据流](#核心架构与数据流)
   - [算法设计与调优](#算法设计与调优)
   - [Swift 编译优化](#swift-编译优化)
4. [🔨 编译与维护命令](#-编译与维护命令)

---

## 🔌 环境准备与音频路由 (BlackHole 设置)

由于 macOS 系统架构的安全与隐私设计，应用无法直接捕获物理扬声器播放的系统音频。为了在物理设备播放声音的同时允许 Wavebar 捕获音频信号，需配置虚拟音频回环设备（如 BlackHole 2ch）和多输出设备。

### 步骤 1: 安装 BlackHole 2ch
1. 打开终端并运行以下 Homebrew 命令：
   ```bash
   brew install blackhole-2ch
   ```
   *(亦可前往 BlackHole 官网下载并安装相应的 `.pkg` 安装包。)*

### 步骤 2: 在“音频 MIDI 设置”中创建多输出设备
1. 打开 macOS 的 **音频 MIDI 设置 (Audio MIDI Setup)** 应用。
2. 点击窗口左下角的 **加号 (+)** 按钮，选择 **创建多输出设备 (Create Multi-Output Device)**。
3. 在设备列表中进行勾选：
   - 勾选您的物理播放设备（如“内置扬声器”、“External Headphones”等）。
   - 勾选 **BlackHole 2ch**。
   - *注意：建议将物理播放设备置于首位以保持主时钟同步。*
4. 勾选 **BlackHole 2ch** 栏的 **漂移矫正 (Drift Correction)** 开关，物理播放设备保持不勾选。这能保证多设备输出时的音频同步，防止画音不同步或出现爆音。

### 步骤 3: 将多输出设备设为 macOS 声音主输出
1. 打开 macOS 的 **系统设置 -> 声音 (Sound)**。
2. 在 **输出 (Output)** 设备列表中，选中刚刚创建的 **多输出设备**。

---

### 音量控制与设备联动 (Volume Link)

#### 系统的设计限制
使用“多输出设备”时，macOS 在 HAL 层面会关闭该主设备的统一音量控制，系统默认音量调节滑块变灰，且键盘音量键（F11 / F12）不可用。

#### 传统方案的限制
若通过某些第三方工具强行同步调节所有子设备的音量，会将虚拟声卡 BlackHole 的通道输出音量同比例调小。这会导致输入到可视化应用的音频信号减弱，使得频谱柱在低音量时几乎无法响应。

#### Wavebar 的 Volume Link 联动逻辑
Wavebar 在设置中集成了 **`VOLUME LINK` (智能音量联动)** 功能，其工作机制如下：
1. **虚拟通道音量锁死**：实时查询当前输出设备，如检测到多输出设备，则自动将过滤出的虚拟通道（如 `BlackHole`）音量固定在 100% 满额状态（1.0），确保频谱分析输入信号幅度保持饱满。
2. **物理音量独立调节**：键盘音量控制热键仅对实际物理输出设备（如耳机、内置扬声器）进行标准的 1/16 格音量梯度微调。
3. **全局热键拦截与阻断**：拦截系统全局音量控制热键事件，防止 macOS 灰色“禁止音量控制”OSD 弹窗显现。

#### 启用方式
1. 点击底栏右侧的 **齿轮 (Settings)** 图标打开设置面板。
2. 勾选 **`VOLUME LINK`** 开关。
3. **授予辅助功能权限**：拦截全局系统音量热键需要系统安全授权。请在弹出的系统面板中，勾选允许 **Wavebar**。

#### 关于麦克风权限与隐私
由于 macOS 将虚拟音频回环设备（如 BlackHole）归类到“音频输入”权限体系中，应用运行时会显示“正在使用麦克风”或请求音频输入权限。Wavebar 全程在本地运行，无网络传输、遥测或远程存储，音频样本仅在内存中用于 FFT 频谱渲染。

---

## 🎛️ 操作手册 (User Manual)

### 1. 悬浮控制栏与设置参数

鼠标悬停在 Wavebar 窗口内时，底部的**半透明悬浮控制栏**会自动淡入，包含一个 **设置 (Settings) 齿轮按钮**。点击该按钮即可展开 **弹出设置面板 (Settings Panel Popover)**。常用调节参数定义如下：

| 参数名称 | 控件类型 | 作用与范围 |
| :--- | :--- | :--- |
| **AUDIO INPUT** | 下拉菜单 | 切换音频捕获源。默认优先连接 `"BlackHole 2ch"`。 |
| **COLOR THEME** | 下拉菜单 | 切换配色主题，提供 4 种色域配置：<br>• `Aurora` (深青到薄荷绿)<br>• `Midnight` (深紫到玫红)<br>• `Sunset` (深红到金黄)<br>• `Silver` (深灰到钛金) |
| **VISUALIZER STYLE** | 下拉菜单 | 切换可视化效果风格：<br>• `Frequency Bars` (柱状频谱)<br>• `3D Particle Flow` (3D 粒子流)<br>• `Cardiogram Wave` (心电图波形) |
| **SENSITIVITY** | 滑块 | 灵敏度增益（`0.3x` ~ `3.0x`）。调整频谱柱/粒子运动的整体缩放比例。 |
| **DECAY SMOOTH** | 滑块 | 平滑衰减速度（`0.03` ~ `0.30`）。滑块越小，波形起伏越灵敏；滑块越大，波形回落越缓慢。 |
| **BARS** | 滑块 | 频谱柱数量（`24` ~ `160`，**仅在 Frequency Bars 风格下显示**）。 |
| **PARTICLE SPEED** | 滑块 | 粒子流动速度倍率（`0.2x` ~ `2.5x`，**仅在 3D Particle Flow 风格下显示**）。 |
| **TURBULENCE STRENGTH** | 滑块 | 湍流风场抖动强度（`0.0x` ~ `2.5x`，**仅在 3D Particle Flow 风格下显示**）。 |
| **VORTEX SIZE** | 滑块 | 漩涡环绕半径缩放因子（`0.3x` ~ `2.0x`，**仅在 3D Particle Flow 风格下显示**）。 |
| **CARDIOGRAM SPEED** | 滑块 | 心电波形流动与刷新速度（`0.2x` ~ `2.5x`，**仅在 Cardiogram Wave 风格下显示**）。 |
| **GRID INTENSITY** | 滑块 | 背景医疗网格的半透明强度（`0.0` ~ `1.0`，**仅在 Cardiogram Wave 风格下显示**）。 |
| **LINE THICKNESS** | 滑块 | 波形线条及发光核心的粗细（`0.5x` ~ `3.0x`，**仅在 Cardiogram Wave 风格下显示**）。 |
| **WAVE AMPLITUDE** | 滑块 | 波形纵向跳动振幅增益（`0.2x` ~ `3.0x`，**仅在 Cardiogram Wave 风格下显示**）。 |
| **BASELINE JITTER** | 滑块 | 基线高频电子抖动微噪强度（`0.0` ~ `3.0`，**仅在 Cardiogram Wave 风格下显示**）。 |
| **SHOW HUD** | 勾选框 | 是否显示 HR BPM 医疗数字面板与闪烁红心（**仅在 Cardiogram Wave 风格下显示**）。 |
| **LOW EQ** | 勾选框 | 低频前级增强。开启时，对低音频段（50Hz-200Hz）应用约 `1.8x` 的增益补偿，增强鼓点和低音的视觉表现力。 |
| **VOLUME LINK** | 勾选框 | 智能音量联动。开启后配合辅助功能授权实现物理/虚拟设备的音量分流调节。 |
| **DESKTOP BLEND MODE** | 勾选框 | 桌面融入模式。开启后隐藏窗口边框与系统阴影，背景变为完全透明，且通过渐变羽化遮罩边缘，使频谱融入壁纸。 |
| **LIQUID FX** | 滑块 | GPU 液态融合强度（`0.0` ~ `1.0`）。控制 Metal Metaball 滤镜的柔边和融合阈值，使相邻频谱柱产生液体流动融合效果。 |
| **BASS LIMIT** | 滑块 | 频谱分析低音下限（`20Hz` ~ `1000Hz`），用于过滤低于该频段的亚音速噪声与多余低频。 |
| **TREBLE LIMIT** | 滑块 | 频谱分析高音上限（`1000Hz` ~ `22000Hz`），用于截断高于该频段的超声波及静音噪波。 |

### 2. 自适应紧凑布局 (Compact Layout)
- **紧凑视图触发**：当窗口高度小于 `100` px 或宽度小于 `380` px 时，界面自动切换为无边框的紧凑视图（直角边缘），更利于作为状态栏或桌面极简挂件展示。
- **动态发光优化**：紧凑视图下会自动压缩发光图层的模糊半径和缩放系数，避免发光区超出微型窗口边界，且关闭高亮边框以腾出最大画布空间用于频谱展示。
- **悬浮遮罩与交互**：无论何种窗口尺寸，悬浮控制栏均通过鼠标滑入（Hover）动态展示和淡出，提供一致的操作便利性。

### 3. 桌面融入模式 (Desktop Blend Mode)
开启桌面融入模式后，应用切换为以下逻辑：
- **隐藏窗口特征**：关闭 macOS 窗口边缘阴影 (`window.hasShadow = false`) 且隐藏 SwiftUI 高亮边框线。
- **悬浮无感背景**：
  - **鼠标移出窗口时**：背景变为 100% 透明 (`opacity = 0.0`)，仅在桌面上渲染频谱线条和发光层。
  - **鼠标滑入窗口时**：背景与控制栏在 `0.3` 秒内平滑渐变淡入，恢复磨砂黑色质感，便于用户拖拽窗口、调节参数。
- **边缘羽化遮罩**：顶部边缘通过对数渐变遮罩渲染，消除了生硬的几何分界线。

### 4. 配置持久化与窗口恢复
- **配置保存**：所有调节参数（包括配色、风格、滑块参数、低频增强、桌面融入状态等）在发生改变的瞬时自动保存至 `UserDefaults`，重启应用后直接恢复。
- **设备识别**：音频捕获设备通过名称字符串（而非易变 ID）持久化，保证设备在重启或插拔后正确重新绑定。
- **窗口尺寸恢复**：程序退出时记录当前窗口的分辨率大小。重启时对尺寸进行合法性边界校验（最窄 160 px，最矮 30 px，不超过显示器最大分辨率），合法则恢复，异常则重置为默认推荐的 `750x200` px。

---

## 💻 二次开发手册 (Developer Guide)

### 项目文件结构

```text
wavebar/
├── Package.swift            # SPM 配置文件，声明 macOS 14+ 平台，排除 AppIcon.icns 资源
├── Makefile                 # 快捷构建工具
├── Sources/
│   ├── main.swift           # 独立可执行程序引导入口，调用 WavebarApp.main()
│   ├── WavebarApp.swift     # SwiftUI App 声明，通过 NSApplicationDelegate 激活前台进程级别
│   ├── MainView.swift       # 核心 GUI 视图，使用 Canvas + VSYNC CADisplayLink 驱动界面渲染
│   ├── RingBuffer.swift     # 线程安全双端环形缓冲区 (Float)
│   ├── AudioEngineManager.swift # CoreAudio 硬件捕获与设备状态查询
│   ├── FFTProcessor.swift   # 基于 Accelerate/vDSP 的 FFT 快速傅里叶变换处理器
│   ├── SpectrumAnalyzer.swift   # 对数分桶、EQ 曲线、自动增益与 Attack/Release 动力学分析器
│   ├── VolumeLinkManager.swift  # 拦截系统全局音量控制键并管理多输出设备的物理/虚拟通道音量
│   ├── VisualizerTheme.swift    # 预设渐变配色主题
│   ├── LiquidGel.metal      # Metal 着色器，负责 GPU 液态 Metaball 物理效果渲染
│   ├── default.metallib     # 编译后的 Metal 库资源
│   ├── AppIcon.icns         # 编译后的 native macOS 矢量及多分辨率应用图标
│   └── Visualizers/         # 可视化特效组件包
│       ├── FrequencyBarsVisualizer.swift # 传统柱状频谱渲染逻辑
│       ├── VortexParticleVisualizer.swift  # 3D 空气动力粒子涡流仿真渲染逻辑
│       └── CardiogramVisualizer.swift  # 医疗监视器 HUD 风格心电图波形渲染逻辑
├── script/
│   ├── build_and_run.sh     # 核心打包构建脚本，负责 app 结构拼装、资源拷贝与 Info.plist 自动生成
│   ├── ProcessIcon.swift    # 图标处理辅助代码
│   └── generate_icns.sh     # 图标全分辨率生成与打包编译脚本
└── dist/
    └── Wavebar.app          # 构建出的标准 macOS 独立 App Bundle 包
```

---

### 核心架构与数据流

Wavebar 采用**实时音频线程**与**UI 渲染线程**分离的双线程解耦架构：

```text
【 硬件层: BlackHole 输入设备 】
             │  (实时 PCM Float 采样流)
             ▼
【 实时音频线程: AVAudioEngine Input Tap 】
             │  (零堆内存分配 Copy，Mono 合流)
             ▼
【 线程安全环形缓冲区: AudioRingBuffer 】
             │  
   ─── 线程隔离边界 (主线程 CADisplayLink VSYNC 硬件同步拉取) ───
             │  
             ▼
【 VSYNC 硬件刷新率对齐事件: CADisplayLink tick 】
             │  (读取最新 1024 采样点)
             ├─►【 FFTProcessor (Apply Hann Window -> vDSP Real FFT -> Magnitudes) 】
             │
             ├─►【 SpectrumAnalyzer (对数分桶 -> EQ 增益 -> 自动增益 -> 动力学平滑) 】
             │
             ▼  (更新渲染状态数据)
【 SwiftUI 渲染层: ZStack / Canvas / Metal Layer / Gradient 】
```

1. **音频捕获（实时高优先级线程）**：
   在 `AVAudioEngine` 的音频捕获总线回调中执行。该线程通过预分配的 `downmixBuffer` 对多通道音频进行 mono 平均合流，快速写入 `AudioRingBuffer`。**此回调中避免进行任何堆内存分配、日志打印或 SwiftUI 状态属性的直接写操作，以消除由于锁或 GC 导致音频流瞬态阻断的可能**。
2. **频谱分析与渲染（主线程 VSYNC 驱动）**：
   由硬件刷新对齐的 `CADisplayLink` 触发回调。依据当前显示器的实际刷新率（60Hz/120Hz/144Hz 等）从环形缓冲区安全拉取最新的 1024 个采样点，经 `FFTProcessor` 运算生成频域能量，再由 `SpectrumAnalyzer` 处理平滑、自动增益以及瞬态低音脉冲判定。所有变化直接通过单路径合并批处理（Single-Path Batching）机制投射在 SwiftUI Canvas 上，确保在高刷渲染下仍具有极低的 CPU 消耗与内存开销。

---

### 算法设计与调优

#### 1. 频域对数分桶算法 (Logarithmic Binning)
* **代码位置**：`Sources/SpectrumAnalyzer.swift` -> `regenerateBucketConfigs()`
* **原理**：
  为避免线性分桶造成低频段信息拥挤在最前几个分桶，算法在用户指定的最低分析频率 $f_{min}$ 和最高频率 $f_{max}$ 之间引入对数递增公式。第 $k$ 个桶的起始频率计算公式为：
  $$f_{start} = f_{min} \times \left(\frac{f_{max}}{f_{min}}\right)^{\frac{k}{M}}$$
  其中 $M$ 为总分桶数。这确保了低频段有足够窄的频带宽，提供高精细度的低音分辨率。

#### 2. EQ 增益与高频声学倾斜补偿 (Equalizer & Spectral Tilt Curve)
* **代码位置**：`Sources/SpectrumAnalyzer.swift` -> `getEQGain(frequency:)`
* **原理**：
  - **低频补偿**：在勾选 `LOW EQ` 时，低音（低于 200Hz）应用恒定的 `1.8x` 前级放大，并在 200Hz - 2000Hz 之间平滑过渡至 `1.0x`。
  - **高频衰减补偿**：由于音频物理信号具有 $1/f$ 的粉红噪声衰减特性，高频能量天然较弱。应用引入了指数声学倾斜补偿因子 $\text{tilt} = (f / 200)^{0.65}$，以消除高低频的能量落差，使高低频的起伏幅度分布相对均衡。

#### 3. 动力学控制 (Dynamics: Attack / Release)
* **代码位置**：`Sources/SpectrumAnalyzer.swift` -> `processFrame(magnitudes:)`
* **原理**：
  - 上升阶段使用 `attackCoeff = 1.0`，保证瞬态响应零延时，音浪起伏更清脆跟手。
  - 下降跌落时采用平滑衰减系数 `decayCoeff`（可由 UI 绑定的平滑度滑块微调，范围 `0.03` 至 `0.30`）。
  - 动力学迭代公式如下：
    $$V_{new} = V_{prev} + \text{Coeff} \times (V_{target} - V_{prev})$$

#### 4. 局部与全局自适应混合归一化 (Decoupled Global-Local Normalization)
* **代码位置**：`Sources/SpectrumAnalyzer.swift` -> `processFrame(magnitudes:)`
* **原理**：
  - **全局自适应追踪**：维护一个宏观历史峰值 `runningMax`，每帧以低权重（如 `0.006`）融合当前帧的最大幅值，缓慢跟踪音轨的整体能量起伏。
  - **局部自适应追踪**：为每个分桶维护专属的局部历史最大值 `runningMaxes[k]`（以 `0.008` 的速度融合），避免极强的低音或人声爆音对其他频段产生压制。
  - **加权混合归一化**：采用 **45% 全局上限 + 55% 局部上限** 进行归一化映射：
    $$\text{blendedMax} = (\text{runningMax} \times 0.45) + (\text{localMax} \times 0.55)$$
  - **局部噪声门禁**：将局部最大值的底限锁定为 `0.01`，以过滤底噪与环境噪声，保证静音时的画面干净。

#### 5. 瞬态重低音脉冲检测 (Beat Radial Glow)
* **代码位置**：`Sources/SpectrumAnalyzer.swift` -> `processFrame(magnitudes:)`
* **原理**：
  提取 `50Hz - 180Hz` 低音频段的即时平均能量 `bassEnergy`。同时维护基准均值 `bassAverage = bassAverage * 0.97 + bassEnergy * 0.03`。通过计算即时低音瞬态能量比 `ratio = bassEnergy / bassAverage`，利用幂级非线性映射模型导出无级连续的脉冲强度：
  $$\text{pulseGlow} = \max\left(\text{pulseGlow}, \min\left(1.8, \text{excessRatio}^{2.0} \times 1.6 \times \text{energyFactor}\right)\right)$$
  其中超额瞬态比 `excessRatio = max(0.0, ratio - 1.0)`，能量门禁系数 `energyFactor = min(1.0, bassEnergy / 0.02)`。此参数在每一帧以指数阻尼衰减（`* 0.86`），用于驱动背景霓虹发光层的扩散半径和色彩高亮闪烁强度。

#### 6. 3D 粒子涡流仿真算法 (3D Vortex Flow Simulation)
* **代码位置**：`Sources/Visualizers/VortexParticleVisualizer.swift`
* **原理**：
  - **3D 到 2D 投影**：三维空间坐标依据经典的透视投影矩阵转换为屏幕平面坐标：
    $$x_{screen} = \text{centerX} + \frac{x \times fov}{z + fov}, \quad y_{screen} = \text{centerY} + \frac{y \times fov}{z + fov}$$
  - **双轴绕行与中央编织**：两个对称漩涡（代表声信号左右声道特征）在流向中央（$z$ 轴减小）时，粒子轨道会向中央轴线收缩卷吸，呈三维编织态合并卷绕，模拟出翼尖涡流的流体力学运动趋势。
  - **多轴谐波摄像机**：摄像机的视角在三维坐标中根据时间变量做绕 $x$、$y$、$z$ 轴的低频正弦谐波回旋，同时在遇到强重低音（`pulseGlow`）冲击时触发 Z-depth 深度变焦（Camera Zoom Warp）。
  - **双粒子子系统**：
    - **高速核心电火花 (Tangential Sparks)**：流速极快、极细密的粒子，在低音或高音激发下沿着漩涡核心切向喷射，呈现高能脉冲。
    - **环绕微尘 (Ambient Dust)**：大颗粒度、低速度的微尘粒子，在涡流外围慢速盘旋，表现空间立体环绕感。
  - **粒子温度色谱映射**：粒子的色彩渲染根据其当前的三维流体速度、在涡流核心的位置以及距离生成的时间进行混合。高能核心粒子呈现白炽的霓虹亮色，流向尾迹边缘时则平滑演变为柔和的紫色和深琥珀色。

#### 7. GPU 液态 Metaball 混合 (Liquid Gel Shading)
* **代码位置**：`Sources/LiquidGel.metal`
* **原理**：
  在启用 `LIQUID FX` 时，Canvas 被渲染为离屏纹理并在 GPU 上应用 MSL 着色器。该着色器在每个像素的局部区域执行高效的双向盒状模糊（Bilateral Box Blur），随后根据 UI 输入的阈值进行非线性阶梯截断（Thresholding）。这使相近的图形元素在边缘接触时能够像液态汞或元球一样发生粘性融合，形成液态流体质感。

#### 8. 阻尼弹簧物理抖动 (Spring-Damped Camera Shake)
* **代码位置**：`Sources/MainView.swift` -> `DisplayLinkAction` 回调与 Canvas 布局
* **原理**：
  在 VSYNC 帧驱动中引入简谐阻尼物理弹簧模型：
  $$F = -k \cdot x - c \cdot v$$
  where $k=0.16$, $c=0.14$. 当重低音脉冲判定检测到超强鼓点冲击时，向下的瞬时初始速度脉冲 `shakeVelocity = glow * 3.5` 注入该系统。使得整个频谱 Canvas 会像物理喇叭盆体一样产生下沉与阻尼弹回的颤震物理位移，增加了画面的实体冲击感。

#### 9. 医疗监视器心电波形算法 (Cardiogram Wave HUD Simulation)
* **代码位置**：`Sources/Visualizers/CardiogramVisualizer.swift`
* **原理**：
  - **对称频域映射 (Symmetric Freq Mapping)**：为解决传统心电图时间轴平移与音乐实时频谱变化相违背的问题，算法对频谱能量进行中心对称映射。屏幕中线（`0.5`）严格映射 **重低音 (Bass)**，而向左和向右外侧对称平移映射 **中音 (Mids)** 与 **高音 (Treble)**。当重低音重击时，会在屏幕中心产生类似 QRS 心电复合物的陡峭巨幅尖峰波形，而中高音旋律则在两侧激起细腻平滑的对称涟漪。
  - **连续高频载波调制 (Continuous Carrier Modulation)**：频谱幅值不仅是静态高度，而是乘以一个高频正弦载波函数 $y_{raw} = \text{height} \times \sin(x \cdot \omega - t \cdot s)$，使纯能量柱变形成连续波动且充满细节的示波器细线。
  - **智能基线偏移与噪声 (Baseline Drift & Jitter)**：加入低频漂移与高频抖动噪声混合模型，让波线产生呼吸般的自然起伏以及细微的高频电子杂讯。
  - **多层重叠矢量笔触 (Multi-layer Glow Rendering)**：在 Canvas 上利用 3 次重叠描边，绘制低透明度超宽霓虹外发光层、中等宽度半透高亮轨迹层以及极细的纯白高亮笔触芯，实现医院级数字心电监视器画质。

---

### Swift 编译优化

#### Modifier Chain 泛型推导超时瓶颈
在 Swift 语言的类型推导机制中，如果在一个复杂的视图树容器上级联挂载大量的 `.onChange` 监听器或其他状态修改器，如：
```swift
View()
  .onChange(of: a) { ... }
  .onChange(of: b) { ... }
  // 级联 8 个以上...
```
Swift 编译器在进行类型推导时会构建出深度嵌套的 `ModifiedContent<ModifiedContent<...>>` 链式强类型泛型。这使得编译器的约束求解器在处理含有大量 `@State` 状态持久化绑定的容器时，面临 $O(N^2)$ 的约束空间搜索开销，导致在大型视图的编译过程中频繁出现类型检查超时（Expression too complex / Swift Compile Timeout）的报错。

#### 解决方案 (Flat State Persistence Observers)
为了将类型检查开销降为 $O(1)$，Wavebar 采用了平铺状态观测者技术。将所有状态的 `.onChange` 参数持久化监听器从主视图树容器的尾部剥离，改为挂载到一组放置在平铺 `ZStack` 里的 zero-sized `Color.clear` 辅助视图上：
```swift
ZStack {
    // 主视图结构
    contentView
    
    // 平铺的状态持久化观测者，相互独立，避免了泛型强类型的嵌套级联
    Group {
        Color.clear.onChange(of: flowSpeedMultiplier) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: "wavebar.flowSpeedMultiplier")
        }
        Color.clear.onChange(of: turbulenceStrength) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: "wavebar.turbulenceStrength")
        }
        Color.clear.onChange(of: vortexSize) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: "wavebar.vortexSize")
        }
        // 其他独立观测器...
    }
}
```
此优化大幅减少了泛型修饰符的嵌套深度，解决了编译超时问题，使整个项目的 Swift 编译耗时保持在数秒以内，提升了二次开发的迭代效率。

---

## 🔨 编译与维护命令

通过根目录下的 `Makefile` 可以快捷管理应用的编译、运行与安装生命周期：

* **编译 Release 生产版本**：
  ```bash
  make build
  ```
  *(编译生成的可执行应用包位于 `dist/Wavebar.app`)*

* **编译并直接运行应用**：
  ```bash
  make run
  ```

* **安装到系统中**：
  ```bash
  make install
  ```
  *(应用将被安全拷贝至系统的 `/Applications/Wavebar.app`)*

* **清理编译缓存与临时产物**：
  ```bash
  make clean
  ```
