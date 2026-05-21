# Wavebar - 原生 macOS 音频频谱可视化器

Wavebar 是一个使用 Swift 和 SwiftUI 开发的高性能、原生 macOS 音频频谱可视化 GUI 应用。它直接通过 CoreAudio 与 AVAudioEngine 捕获系统声音，使用 Accelerate/vDSP 框架进行实时 FFT 频谱分析，采用双线程环形缓冲区设计，并在 SwiftUI Canvas 上利用 VSYNC 硬件帧率同步（支持 ProMotion 120Hz/144Hz）进行极其丝滑的高性能加速渲染。

为了保证极致的视觉观感，Wavebar 采用了高雅的玻璃磨砂设计（Glassmorphism）和高度自适应的动态窗口布局，是您在 macOS 桌面上放置的绝佳 Picture-in-Picture 音乐伴侣。

---

## 📖 目录
1. [🔌 环境准备与音频路由 (BlackHole 设置)](#-环境准备与音频路由-blackhole-设置)
2. [🎛️ 操作手册 (User Manual)](#️-操作手册-user-manual)
   - [快捷手势频段缩放与平移](#1-快捷手势频段缩放与平移-drag-to-zoom--pan)
   - [悬浮控制栏参数详解](#2-悬浮控制栏参数详解)
   - [自适应折叠布局](#3-自适应折叠布局)
   - [配置持久化与启动布局](#4-配置持久化与启动布局)
3. [💻 二次开发手册 (Developer Guide)](#-二次开发手册-developer-guide)
   - [项目文件结构](#项目文件结构)
   - [核心架构与数据流](#核心架构与数据流)
   - [关键参数与算法调优](#关键参数与算法调优)
4. [🔨 编译与维护命令](#-编译与维护命令)

---

## 🔌 环境准备与音频路由 (BlackHole 设置)

由于 macOS 系统架构的安全限制，应用无法直接从系统的物理扬声器捕获播放的 PCM 音频。为了既能通过耳机或扬声器**听到声音**，又能让 Wavebar **捕获并可视化声音**，我们需要配置一个虚拟音频回环设备（BlackHole 2ch）和多输出设备。

请依次执行以下三个步骤完成配置：

### 步骤 1: 安装 BlackHole 2ch

建议安装 **BlackHole 2ch**（2通道版本，延迟极低，完美适配实时可视化）：
*   打开终端并运行以下 Homebrew 命令：
    ```bash
    brew install blackhole-2ch
    ```
*   *如果您没有安装 Homebrew，也可以前往 BlackHole 官网下载对应的 `.pkg` 安装包进行安装。*

### 步骤 2: 在“音频 MIDI 设置”中创建多输出设备
1. 按下快捷键 `Command + 空格键` 召唤 Spotlight，搜索并打开 macOS 自带的 **音频 MIDI 设置 (Audio MIDI Setup)** App。
2. 在弹出的“音频设备”窗口左下角，点击 **加号 (+)** 按钮。
3. 在下拉菜单中选择 **创建多输出设备 (Create Multi-Output Device)**。
4. 在右侧的设备列表中进行勾选：
   *   **优先勾选** 您的物理播放设备（例如：“内置扬声器”、“External Headphones” 或您的外接音箱/声卡）。
   *   **接着勾选** **BlackHole 2ch**。
   *   *提示：建议物理播放设备排在首位以确保主时钟同步。*
5. 针对 **BlackHole 2ch** 一栏，勾选 **“漂移矫正” (Drift Correction)** 开关，物理播放设备保持不勾选。这能有效保证多设备输出时的音频同步，防止画面与耳朵听到产生时间差或爆音。

### 步骤 3: 将多输出设备设为 macOS 声音主输出
1. 打开 macOS 的 **系统设置 -> 声音 (Sound)**。
2. 在 **输出 (Output)** 设备列表中，选中您刚刚创建的 **多输出设备**（通常名为“多输出设备”）。
3. 此时，系统播放的所有音频都将被同时复制分流到您的耳机/扬声器（让您能听到）以及 BlackHole 2ch 回环通道中（让 Wavebar 能够捕获并可视化）。

---

## 🎛️ 操作手册 (User Manual)

### 1. 快捷手势频段缩放与平移 (Drag-to-Zoom & Pan)
除了拖动底部的常规滑块外，Wavebar 搭载了极为现代的**频谱画布快捷手势操作系统**。您可以直接在频谱的柱子上通过**鼠标水平左右拖拽**来缩放和移动您想观察的音域：

*   **左侧缩放区 (画布最左侧 30% 范围)**：
    *   水平拖拽调整**低音下限分析频率 (`fMin`)**。
    *   向左拖动让频段下探到超低音（最低至 `20Hz`），向右拖动则过滤除外低音细节。
*   **右侧缩放区 (画布最右侧 30% 范围)**：
    *   水平拖拽调整**高音上限分析频率 (`fMax`)**。
    *   向右拖动让频段扩展到超高音（最高至 `22kHz`），向左拖动则收窄高频。
*   **中间平移区 (画布中间 40% 范围)**：
    *   水平拖拽**整体平移 (Pan) 观察视口**。
    *   拖拽时，`fMin` 与 `fMax` 以相同的对数比例平移，保持倍频程 span 完美恒定，给您如“滑动相机”般查看整个音轨频段的感觉。
*   **HUD 实时提示**：
    *   拖拽发生时，屏幕上方会优雅淡入一个精美磨砂的 Heads-Up Display (HUD) 浮窗，实时以高亮色彩展示当前操作模式及具体频率边界（例如 `50 Hz ➔ 8.0 kHz`），释放后 1.2 秒自动平滑淡出。

### 2. 悬浮控制栏参数详解
当鼠标悬停在 Wavebar 窗口内时，底部的半透明磨砂控制栏会自动淡入。它提供了以下 8 个精准控制器：

| 参数名称 | 控件类型 | 作用与范围 |
| :--- | :--- | :--- |
| **AUDIO INPUT** | 下拉菜单 | 切换音频捕获源。默认自动优先选中并连接 `"BlackHole 2ch"`，若不可用则智能降级至麦克风或其他物理源。 |
| **COLOR THEME** | 下拉菜单 | 切换配色主题，提供 4 种精心调配的高端色域：<br>• `Aurora` (极光，深青到薄荷绿)<br>• `Midnight` (午夜，深紫到玫红)<br>• `Sunset` (落日，深红到金黄)<br>• `Silver` (银白，深灰到钛金) |
| **SENSITIVITY** | 滑块 | 灵敏度（`0.3x` ~ `3.0x`）。调整频谱的整体放大增益。在音乐音量较小时可适当调高。 |
| **DECAY SMOOTH** | 滑块 | 平滑衰减速度（`0.03` ~ `0.30`）。滑块越往左，频谱柱起伏越灵敏狂野；越往右，跌落越平缓丝滑。 |
| **BARS** | 滑块 | 频谱柱数量（`24` ~ `160`）。系统自动重算宽度布局，平滑自适应。 |
| **LOW BOOST** | 勾选框 | 低频前级均衡增强。开启时，对低音（50Hz-200Hz）应用约 `1.8x` 的前级均衡补偿，中高频呈平滑衰减曲线，使电音、鼓点等低音视觉表现更有冲击力。 |
| **BASS LIMIT** | 滑块 | 低音下限（`20Hz` ~ `1000Hz`），可与手势联动。 |
| **TREBLE LIMIT** | 滑块 | 高音上限（`1000Hz` ~ `22000Hz`），可与手势联动。 |

### 3. 自适应折叠布局
为了适配桌面上置顶缩小的极端轻量化场景，Wavebar 实现了布局自动缩减：
*   **控制栏隐藏**：当窗口高度不足 `180` px 或宽度不足 `720` px 时，底部的悬浮控制栏将自动淡出并隐藏，确保画布只显示纯净的频谱起伏。
*   **手势完全保留**：即使控制栏被完全隐藏折叠，画布上的 **水平拖拽缩放与平移手势** 以及 **HUD** 依然保持 100% 激活可用，您依然可以随时随地用鼠标微调分析频段。

### 4. 配置持久化与启动布局
*   **零手动重复**：所有的调节参数（配色主题、灵敏度、平滑度、低频增强、频谱柱数、高低音限制频率、音频输入设备）均在您修改的瞬间自动通过 `UserDefaults` 完成**立即持久化**，下次打开应用自动加载并恢复先前状态。
*   **智能设备恢复**：音频输入设备通过**设备名称字符串**（而非开机即变的 dynamic CoreAudio 内部 ID）进行持久化，保证重启电脑或拔插外接声卡后依然能完美认出并连回首选输入源。
*   **启动不脏尺寸**：应用启动时不会记忆上一次被拉成畸形的窗口尺寸，而是强制以推荐的 `750x200` px 精准居中呈现在屏幕上（确保默认能完美放下控制栏），之后您可以任意拉伸改变它。
*   **一键安全退出**：点击窗口的关闭按钮，整个应用程序进程会彻底干净地退出，不再遗留在系统后台静默消耗资源。

---

## 💻 二次开发手册 (Developer Guide)

Wavebar 在设计上极其注重性能，避免了在音频回调线程中进行内存分配、控制台日志打印和 SwiftUI 状态无效化重绘。

### 项目文件结构

```text
wavebar/
├── Package.swift            # SPM 配置文件，声明 macOS 14+ 平台与 wavebar 独立执行 target
├── Makefile                 # 快捷构建工具
├── Sources/
│   ├── main.swift           # 独立可执行程序引导入口，调用 WavebarApp.main()
│   ├── WavebarApp.swift     # SwiftUI App 声明，通过 AppDelegate 提升进程激活级别
│   ├── MainView.swift       # 核心 GUI 视图，使用 Canvas + VSYNC CADisplayLink 驱动极其丝滑的渲染
│   ├── RingBuffer.swift     # 线程安全双端环形缓冲区 (浮点数)
│   ├── AudioEngineManager.swift # 封装 CoreAudio 硬件查询与 AVAudioEngine 输入流 Tap
│   ├── FFTProcessor.swift   # 基于 Accelerate/vDSP 的 FFT 核心处理器
│   └── SpectrumAnalyzer.swift   # 对数分桶、EQ 曲线、Auto-Gain 与 Attack/Release 动力学分析器
```

---

### 核心架构与数据流

整个应用的计算与渲染链路采用**双线程解耦架构**：

```text
【 硬件层: BlackHole 输入设备 】
             │  (实时 PCM Float 采样流)
             ▼
【 实时音频线程: AVAudioEngine Input Tap 】
             │  (零堆分配 Copy，Mono 合流)
             ▼
【 线程安全环形缓冲区: AudioRingBuffer 】
             │  
   ─── 线程隔离边界 (主线程 CADisplayLink VSYNC 硬件同步拉取) ───
             │  
             ▼
【 VSYNC 硬件刷新率对齐事件: CADisplayLink tick 】
             │  (读取最新 1024 样本)
             ├─►【 FFTProcessor (Apply Hann Window -> vDSP Real FFT -> Magnitudes) 】
             │
             ├─►【 SpectrumAnalyzer (对数分桶 -> EQ 增益 -> 自动增益 -> 动力学平滑) 】
             │
             ▼  (更新 @Published smoothedHeights / pulseGlow 状态变量)
【 SwiftUI 渲染层: ZStack / Canvas / Gradient 】
```

1.  **音频捕获（实时高优先级线程）**：
    由 `AVAudioEngine` 的音频捕获总线驱动。回调块在系统实时线程执行，为防止音频断流或爆音，该线程使用预分配的 `downmixBuffer` 进行多通道平均合流（Stereo-to-Mono），并以最快速度写入 `AudioRingBuffer`，**绝不执行堆内存分配、NSLog 输出或任何 SwiftUI 属性更改**。
2.  **频谱处理与渲染（主线程 VSYNC 硬件刷新率驱动）**：
    `MainView.swift` 中声明并使用了硬件时钟对齐的 `CADisplayLink`。当系统屏幕刷新（如 ProMotion 120Hz/144Hz）产生 VSYNC 信号时触发回调，安全地从环形缓冲区拉取最新的 1024 个采样点（相比 2048，分析物理延迟减半至 23ms 左右），通过 `FFTProcessor` 运算并由 `SpectrumAnalyzer` 处理平滑。通过单路径合并批处理（Single-Path Batching）机制在 SwiftUI Canvas 上一笔绘制填充，避免高刷下频繁分配与垃圾回收抖动，呈现极其细腻平滑的视觉动画。

---

### 关键参数与算法调优

若想对可视化效果做更深度的个性化改造，可查阅并修改以下核心代码块：

#### 1. 频域范围与分桶算法 (Logarithmic Binning)
*   **代码位置**：`Sources/SpectrumAnalyzer.swift` -> `regenerateBucketConfigs()`
*   **修改指南**：
    *   分析频段限制在最低 `fMin` (默认 50Hz)，最高 `fMax` (默认 8000Hz) 之间。支持用户在界面上动态拖拽缩放或使用滑块调整（最大支持 `20Hz` ~ `22kHz` 的全频段解析）。
    *   采用对数公式分桶，保证了左侧的低音柱子能够捕获窄至数赫兹的精细能量，防止像线性分桶那样低频全挤在第一个柱子：
        $$\text{fStart} = f_{min} \times \left(\frac{f_{max}}{f_{min}}\right)^{\frac{k}{M}}$$

#### 2. 低频增强曲线 (Equalizer Curve)
*   **代码位置**：`Sources/SpectrumAnalyzer.swift` -> `getEQGain(frequency:)`
*   **修改指南**：
    *   提供了连续分段增益曲线：低于 `200Hz` 音频倍率固定增强为 `1.8x`，随后平滑平坠降至极高频的 `0.7x` 左右，以对齐人类对低频鼓声的视觉偏好并收敛超高频背景杂音。
    *   您可以根据喜好重新编写此函数的映射关系（例如设计一个中频人声突出的曲线）。

#### 3. 动态响应控制 (Dynamics: Attack / Release)
*   **代码位置**：`Sources/SpectrumAnalyzer.swift` -> `processFrame(magnitudes:)`
*   **修改指南**：
    *   `attackCoeff` 提升为 `1.0`（瞬态零延迟冲击，使得节奏爆发更凌厉，柱体反应更加灵敏跟手）。
    *   跌落时采用 `currentRelease`（由滑块绑定的平滑衰减系数，范围 `0.03` 至 `0.30`）。
    *   动力学迭代公式为：
        $$V_{new} = V_{prev} + \text{Coeff} \times (V_{target} - V_{prev})$$

#### 4. 自动增益机制 (Autosens / Auto-Gain)
*   **代码位置**：`Sources/SpectrumAnalyzer.swift` -> `processFrame(magnitudes:)` 中的 `runningMax` 更新逻辑。
*   **修改指南**：
    *   应用维持一个随时间缓慢衰减的幅值历史峰值 `runningMax`（每一帧以 `0.006` 的权重融合当前帧的最大幅值，以 `0.994` 的权重融合历史值）。
    *   这保证了在整首音乐大声时频谱柱不会全体顶格，在音乐极其轻柔时又会自动放大细节。最低底噪门限限制在 `0.03`，防止静音时过度放大背景白噪声。

#### 5. 瞬态重低音脉冲检测 (Beat Radial Glow)
*   **代码位置**：`Sources/SpectrumAnalyzer.swift` -> `processFrame(magnitudes:)` 的底端 Bass 部分。
*   **修改指南**：
    *   提取 `50Hz` 到 `180Hz` 频段对应的所有桶能量，计算出即时平均值 `bassEnergy`。
    *   维护一个平滑基准值 `bassAverage = bassAverage * 0.97 + bassEnergy * 0.03`。
    *   当即时低音能量比历史基准能量大出 **35%** (`ratio > 1.35`) 且绝对振幅大于阀值时，判定为一个强击鼓点，将 `pulseGlow` 设为 `1.0`。
    *   `pulseGlow` 随后在每一帧以指数阻尼衰减（`* 0.86`），用来绑定并驱动 MainView 中背景发光层 (`RadialGradient`) 的亮度和大小，实现随节奏脉动闪烁的高端视觉感。

---

## 🔨 编译与维护命令

通过项目根目录下的 `Makefile` 可以快速管理全部生命周期：

*   **编译 Release 生产版本**：
    ```bash
    make build
    ```
    *(编译产物将生成至：`.build/release/wavebar`)*
*   **运行应用**：
    ```bash
    make run
    ```
*   **清理编译缓存与临时目录**：
    ```bash
    make clean
    ```
