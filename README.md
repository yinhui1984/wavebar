# Wavebar - 原生 macOS 音频频谱可视化器

Wavebar 是一个使用 Swift 和 SwiftUI 开发的高性能、原生 macOS 音频频谱可视化 GUI 应用。它直接通过 CoreAudio 与 AVAudioEngine 捕获系统声音，使用 Accelerate/vDSP 框架进行实时 FFT 频谱分析，采用双线程环形缓冲区设计，并在 SwiftUI Canvas 上进行 60 FPS 硬件加速渲染。

---

## 📖 目录
1. [环境准备与音频路由](#-环境准备与音频路由)
2. [操作手册 (User Manual)](#-操作手册-user-manual)
3. [二次开发手册 (Developer Guide)](#-二次开发手册-developer-guide)
   - [项目文件结构](#项目文件结构)
   - [核心架构与数据流](#核心架构与数据流)
   - [关键参数与算法调优](#关键参数与算法调优)
4. [编译与维护命令](#-编译与维护命令)

---

## 🔌 环境准备与音频路由

要捕获 macOS 的系统音频，应用需要借助虚拟音频回环设备。以下为标准的配置流程：

### 1. 安装 BlackHole
建议安装 **BlackHole 2ch**（2通道版本，延迟极低，最适合可视化）：
*   使用 Homebrew 安装：
    ```bash
    brew install blackhole-2ch
    ```

### 2. 配置 macOS 音频输出
1. 打开 macOS **系统设置** -> **声音**。
2. 将 **输出设备** 设置为 **BlackHole 2ch**。
3. *提示：如果您希望在播放音乐时自己也能听到声音，请在 macOS 自带的 “音频 MIDI 设置” (Audio MIDI Setup) 应用中创建一个“多输出设备” (Multi-Output Device)，同时勾选您的扬声器/耳机和 BlackHole 2ch，然后将系统主声音输出设置为该多输出设备。*

---

## 🎛️ 操作手册 (User Manual)

### 1. 编译与首次启动
在项目根目录下执行以下命令编译并启动：
```bash
make build
make run
```

> [!IMPORTANT]
> **麦克风权限申请**：
> 首次启动时，macOS 会弹出安全提示申请“麦克风访问权限”（因为系统将音频输入接口归为麦克风权限范畴）。**必须点击“允许”**，否则 AVAudioEngine 将无法从 BlackHole 捕获任何 PCM 信号，界面会弹出警告或显示为静止。

### 2. 界面控制栏操作
界面底部设计了悬浮的半透明磨砂玻璃控制栏，鼠标移入窗口时会自动淡入显示，移出时淡出，保证极致的纯净观感。

*   **AUDIO INPUT (音频输入选择器)**：
    *   下拉菜单会自动枚举 macOS 当前所有可用的音频输入设备。
    *   默认优先选择包含 "BlackHole 2ch" 的回环通道；如果未找到，会自动降级选择其他输入源（如内置麦克风）。
*   **SENSITIVITY (灵敏度)**：
    *   控制频谱高度的整体放大倍数（范围：`0.3` ~ `3.0`，默认 `1.0`）。如果播放的音乐振幅较小，可适当拉大。
*   **DECAY SMOOTH (平滑释放速度)**：
    *   控制频谱柱下落时的平滑衰减系数（范围：`0.03` ~ `0.30`，默认 `0.12`）。
    *   值越小，柱子下落越慢，频谱越显柔和流动；值越大，柱子下落越快，节奏感和瞬态响应更强（更接近 CAVA 的凌厉感）。
*   **BARS (频谱柱数量)**：
    *   动态调节频谱的频段分桶数量（范围：`24` ~ `96`，步长 `4`）。Canvas 绘制层会自动重算布局并以流畅的平滑动画自适应窗口宽度。
*   **LOW EQ (低频增强)**：
    *   勾选框开关。开启时，对低音（50Hz-200Hz）应用约 `1.8x` 的前级均衡补偿，中高频呈平滑衰减曲线，使电音、鼓点等低音视觉表现更有冲击力。

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
│   ├── MainView.swift       # 核心 GUI 视图，使用 Canvas + 60Hz 计时器驱动渲染
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
   ─── 线程隔离边界 (主线程 60Hz Timer 轮询拉取) ───
             │  
             ▼
【 60 FPS 计时器事件: .onReceive(timer) 】
             │  (读取最新 2048 样本)
             ├─►【 FFTProcessor (Apply Hann Window -> vDSP Real FFT -> Magnitudes) 】
             │
             ├─►【 SpectrumAnalyzer (对数分桶 -> EQ 增益 -> 自动增益 -> 动力学平滑) 】
             │
             ▼  (更新 @Published smoothedHeights / pulseGlow 状态变量)
【 SwiftUI 渲染层: ZStack / Canvas / Gradient 】
```

1.  **音频捕获（实时高优先级线程）**：
    由 `AVAudioEngine` 的音频捕获总线驱动。回调块在系统实时线程执行，为防止音频断流或爆音，该线程使用预分配的 `downmixBuffer` 进行多通道平均合流（Stereo-to-Mono），并以最快速度写入 `AudioRingBuffer`，**绝不执行堆内存分配、NSLog 输出或任何 SwiftUI 属性更改**。
2.  **频谱处理与渲染（主线程 60Hz 驱动）**：
    `MainView.swift` 中声明了一个频率为 60Hz 的主线程定时器 (`Timer.publish`)。定时器事件触发时，在外部事件上下文安全读取环形缓冲区的最新 2048 个采样点，调用 `FFTProcessor` 运算，并由 `SpectrumAnalyzer` 处理平滑度。这些计算结果更新至 Observable 对象的 `@Published` 属性，以最优雅的活性机制通知并触发 Canvas 完成 Metal 渲染。

---

### 关键参数与算法调优

若想对可视化效果做更深度的个性化改造，可查阅并修改以下核心代码块：

#### 1. 频域范围与分桶算法 (Logarithmic Binning)
*   **代码位置**：`Sources/SpectrumAnalyzer.swift` -> `regenerateBucketConfigs()`
*   **修改指南**：
    *   目前分析频段限制在最低 `50.0` Hz，最高 `8000.0` Hz 之间。如果想展示更多超高音细节，可将 `fMax` 改为 `16000.0` 或 `20000.0`。
    *   采用近似对数公式分桶：
        $$\text{fStart} = f_{min} \times \left(\frac{f_{max}}{f_{min}}\right)^{\frac{k}{M}}$$
    *   公式保证了左侧的低音柱子能够捕获窄至数赫兹的精细能量，防止像线性分桶那样低频全挤在第一个柱子。

#### 2. 低频增强曲线 (Equalizer Curve)
*   **代码位置**：`Sources/SpectrumAnalyzer.swift` -> `getEQGain(frequency:)`
*   **修改指南**：
    *   提供了 smooth 连续分段增益曲线：`<=200Hz` 倍率固定为 `1.8`，随后平滑递减至高频的 `0.7` 倍。
    *   您可以根据喜好重新编写此函数的映射关系（例如设计一个中频人声突出的曲线）。

#### 3. 动态响应控制 (Dynamics: Attack / Release)
*   **代码位置**：`Sources/SpectrumAnalyzer.swift` -> `processFrame(magnitudes:)`
*   **修改指南**：
    *   `attackCoeff` 固定为 `0.65`（超快速攀升，使频谱柱击鼓时能瞬间冲顶）。
    *   下落时采用 `currentRelease`（由滑块绑定的平滑参数，范围 `0.03` 至 `0.30`）。
    *   动力学迭代公式为：
        $$V_{new} = V_{prev} + \text{Coeff} \times (V_{target} - V_{prev})$$

#### 4. 自动增益机制 (Autosens / Auto-Gain)
*   **代码位置**：`Sources/SpectrumAnalyzer.swift` -> `processFrame(magnitudes:)` 中的 `runningMax` 更新逻辑。
*   **修改指南**：
    *   应用通过维持一个随时间缓慢指数衰减的幅值最大值 `runningMax`（每一帧以 `0.006` 的权重融合当前帧的最大幅值，以 `0.994` 的权重融合历史值）。
    *   这保证了在整首音乐大声时频谱柱不会全体顶格，在音乐极其轻柔时又会自动放大细节。最低底噪门限限制在 `0.03`，防止静音时过度放大背景白噪声。

#### 5. 瞬态重低音脉冲检测 (Beat Radial Glow)
*   **代码位置**：`Sources/SpectrumAnalyzer.swift` -> `processFrame(magnitudes:)` 的底端 Bass 部分。
*   **修改指南**：
    *   提取 `50Hz` 到 `180Hz` 频段对应的所有桶能量，计算出即时平均值 `bassEnergy`。
    *   维护一个平滑基准值 `bassAverage = bassAverage * 0.97 + bassEnergy * 0.03`。
    *   当即时低音能量比历史基准能量大出 **35%** (`ratio > 1.35`) 且绝对振幅大于阀值时，判定为一个强击鼓点，将 `pulseGlow` 设为 `1.0`。
    *   `pulseGlow` 随后在每一帧乘以衰减率 `0.86` 指数淡出，用来绑定并驱动 MainView 中背景发光层 (`RadialGradient`) 的亮度和大小，实现随节奏脉动闪烁的高端视觉感。

---

## 🔨 编译与维护命令

通过项目根目录下的 `Makefile` 可以快速管理全部生命周期：

*   **编译 Release 生产版本**：
    ```bash
    make build
    ```
    *(二进制文件生成至：`.build/release/wavebar`)*
*   **运行应用**：
    ```bash
    make run
    ```
*   **清理编译缓存与临时目录**：
    ```bash
    make clean
    ```
