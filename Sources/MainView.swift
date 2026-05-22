import SwiftUI
import AVFoundation
import CoreAudio
import QuartzCore

/// Pre-allocated scratch buffers to prevent 60 FPS garbage collection pressure.
private final class DSPBufferHolder {
    var sampleBuffer: [Float]
    var magnitudes: [Float]
    
    init(fftSize: Int) {
        self.sampleBuffer = [Float](repeating: 0.0, count: fftSize)
        self.magnitudes = [Float](repeating: 0.0, count: fftSize / 2)
    }
}


public struct MainView: View {
    @ObservedObject var audioEngineManager: AudioEngineManager
    @ObservedObject var spectrumAnalyzer: SpectrumAnalyzer
    @ObservedObject var volumeLinkManager = VolumeLinkManager.shared
    let ringBuffer: AudioRingBuffer
    let fftProcessor: FFTProcessor
    
    @State private var bufferHolder: DSPBufferHolder
    @State private var showControls: Bool = false
    @State private var showSettings: Bool = false
    @State private var selectedTheme: VisualizerTheme = {
        if let saved = UserDefaults.standard.string(forKey: "wavebar.selectedTheme"),
           let theme = VisualizerTheme(rawValue: saved) {
            return theme
        }
        return .aurora
    }()
    
    @State private var displayLinkAction: DisplayLinkAction? = nil
    @State private var shakeOffset: CGFloat = 0.0
    @State private var shakeVelocity: CGFloat = 0.0
    @State private var liquidIntensity: Double = {
        if let saved = UserDefaults.standard.object(forKey: "wavebar.liquidIntensity") as? Double {
            return min(max(saved, 0.0), 1.0)
        }
        if let legacyEnabled = UserDefaults.standard.object(forKey: "wavebar.isLiquidMode") as? Bool {
            return legacyEnabled ? 0.55 : 0.0
        }
        return 0.55
    }()
    @State private var hideBorderAndShadow: Bool = {
        UserDefaults.standard.bool(forKey: "wavebar.hideBorderAndShadow")
    }()    
    public init(
        audioEngineManager: AudioEngineManager,
        spectrumAnalyzer: SpectrumAnalyzer,
        ringBuffer: AudioRingBuffer,
        fftProcessor: FFTProcessor
    ) {
        self.audioEngineManager = audioEngineManager
        self.spectrumAnalyzer = spectrumAnalyzer
        self.ringBuffer = ringBuffer
        self.fftProcessor = fftProcessor
        
        // Instantiate the scratch buffers container
        _bufferHolder = State(initialValue: DSPBufferHolder(fftSize: fftProcessor.fftSize))
    }
    
    public var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.height < 100 || geometry.size.width < 380
            let cornerRadius: CGFloat = isCompact ? 0 : 16
            let glowVal = spectrumAnalyzer.pulseGlow
            
            let glowBlur: CGFloat = {
                if isCompact {
                    let baseBlur = max(3.0, geometry.size.height * 0.12)
                    return baseBlur + CGFloat(glowVal) * (geometry.size.height * 0.08)
                } else {
                    return 20 + CGFloat(glowVal) * 15
                }
            }()
            
            let glowOpacity: Double = {
                if isCompact {
                    return 0.25 + Double(glowVal) * 0.45
                } else {
                    return 0.08 + Double(glowVal) * 0.38
                }
            }()
            
            ZStack {
                // 1. Translucent Deep Space Glass Backdrop
                Color(red: 0.02, green: 0.02, blue: 0.04).opacity(isCompact ? 0.6 : 0.4)
                    .background(.ultraThinMaterial)
                    .opacity(hideBorderAndShadow ? (showControls ? 1.0 : 0.0) : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: showControls)
                    .mask(
                        Group {
                            if hideBorderAndShadow {
                                LinearGradient(
                                    colors: [.clear, .black.opacity(0.8), .black],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            } else {
                                Color.black
                            }
                        }
                    )
                
                // 2. Inner Nebula Glow Backdrop
                LinearGradient(
                    gradient: Gradient(colors: selectedTheme.colors),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .blur(radius: glowBlur)
                .opacity(glowOpacity)
                .scaleEffect(1.0 + CGFloat(glowVal) * 0.05)
                .blendMode(.screen)
                
                // 3. Hardware-Accelerated Spectrum Canvas (Driven reactively by @Published smoothedHeights)
                let spectrumCanvas = Canvas { context, size in
                    let heights = spectrumAnalyzer.smoothedHeights
                    let count = heights.count
                    guard count > 0 else { return }
                    
                    let isSmall = size.width < 320
                    let spacing: CGFloat = isSmall ? 1.5 : 2.5
                    let minBarWidthAndSpacing: CGFloat = isSmall ? 3.5 : 5.0
                    let maxBars = max(12, Int(size.width / minBarWidthAndSpacing))
                    let finalCount = min(count, maxBars)
                    let totalSpacing = spacing * CGFloat(finalCount - 1)
                    let barWidth = max(1.0, (size.width - totalSpacing) / CGFloat(finalCount))
                    
                    // Beat-driven overall canvas resonant vertical scaling
                    let pulseScale = 1.0 + CGFloat(spectrumAnalyzer.pulseGlow) * 0.08
                    let topPadding: CGFloat = 0
                    let bottomPadding: CGFloat = 2
                    let maxBarHeight = max(10.0, size.height - topPadding - bottomPadding)
                    let gradientTopY = topPadding
                    
                    // Batch all bars into a single path
                    var combinedPath = Path()
                    for i in 0..<finalCount {
                        let originalIndex: Int
                        if finalCount == count {
                            originalIndex = i
                        } else {
                            originalIndex = Int(round(Double(i) * Double(count - 1) / Double(finalCount - 1)))
                        }
                        let valFraction = CGFloat(heights[max(0, min(originalIndex, count - 1))])
                        let barHeight = max(1.5, valFraction * maxBarHeight * pulseScale)
                        let x = CGFloat(i) * (barWidth + spacing)
                        let y = size.height - barHeight - bottomPadding
                        let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                        let cornerRadius = min(barWidth / 2, 3)
                        combinedPath.addRoundedRect(in: rect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
                    }
                    
                    // Emission flash: blend gradient colors towards white on strong beats
                    let beatFlash = Double(spectrumAnalyzer.pulseGlow)
                    let baseColors = selectedTheme.colors
                    let blendedColors = baseColors.enumerated().map { index, color -> Color in
                        let factor = Double(index) / Double(baseColors.count - 1)
                        let flashWeight = min(1.0, beatFlash * 0.65 * factor)
                        return color.blend(with: .white, weight: flashWeight)
                    }
                    
                    let barGradient = Gradient(colors: blendedColors)
                    context.fill(
                        combinedPath,
                        with: .linearGradient(
                            barGradient,
                            startPoint: CGPoint(x: size.width / 2, y: size.height - 6),
                            endPoint: CGPoint(x: size.width / 2, y: gradientTopY)
                        )
                    )
                }
                
                spectrumCanvas
                .overlay {
                    if liquidIntensity > 0.001 {
                        // Keep the plain spectrum visible underneath; Liquid FX is an enhancement layer only.
                        spectrumCanvas
                            .layerEffect(
                                ShaderLibrary.bundle(.module).liquidGelShader(
                                    .float2(Float(geometry.size.width), Float(geometry.size.height)),
                                    .float(Float(spectrumAnalyzer.pulseGlow)),
                                    .float(Float(liquidIntensity))
                                ),
                                maxSampleOffset: CGSize(width: 8, height: 8)
                            )
                            .opacity(liquidIntensity)
                            .allowsHitTesting(false)
                    }
                }
                .offset(y: shakeOffset)
                .edgesIgnoringSafeArea(.horizontal)
                .contentShape(Rectangle())
                
                // 4. Input Failure Overlay Warning
                if let error = audioEngineManager.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundColor(.amberPrimary)
                        Text(error)
                            .font(.headline)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        
                        Button("Refresh Devices") {
                            audioEngineManager.refreshDevices()
                            audioEngineManager.autoSelectDevice()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.teal)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .shadow(radius: 10)
                }
                
                // 5. Floating Frosted Control Bar
                VStack {
                    Spacer()
                    if showControls || showSettings {
                        HStack(spacing: 0) {
                            Button {
                                showSettings.toggle()
                                showControls = true
                            } label: {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.teal)
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                            .help("Settings")
                            .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                                settingsPanel
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.4), radius: 10, y: 5)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 16)
                
                // 4. Accent Border on top of content
                if !isCompact && !hideBorderAndShadow {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { inside in
                if showSettings {
                    showControls = true
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showControls = inside
                    }
                }
                NotificationCenter.default.post(name: Notification.Name("wavebar.windowHoverStateChanged"), object: inside)
            }
            .onAppear {
                displayLinkAction = DisplayLinkAction {
                    // A. Read latest audio frames and run DSP calculations
                    let fftSize = fftProcessor.fftSize
                    spectrumAnalyzer.updateSampleRate(audioEngineManager.sampleRate)
                    
                    ringBuffer.readLatest(count: fftSize, into: &bufferHolder.sampleBuffer)
                    fftProcessor.analyze(samples: bufferHolder.sampleBuffer, magnitudes: &bufferHolder.magnitudes)
                    spectrumAnalyzer.processFrame(magnitudes: bufferHolder.magnitudes)
                    
                    // B. Spring-Damped Camera Shake Physics Simulation
                    let glow = CGFloat(spectrumAnalyzer.pulseGlow)
                    if glow > 0.9 && abs(shakeOffset) < 0.2 {
                        // Apply a physical impulse downwards on heavy beats
                        shakeVelocity = glow * 3.5
                    }
                    
                    // Spring equation: force = -k * x - c * v
                    let k: CGFloat = 0.16 // Spring stiffness constant
                    let c: CGFloat = 0.14 // Damping coefficient to prevent infinite oscillation
                    let force = -k * shakeOffset - c * shakeVelocity
                    shakeVelocity += force
                    shakeOffset += shakeVelocity
                }
            }
            .onDisappear {
                displayLinkAction?.invalidate()
                displayLinkAction = nil
            }
            .onChange(of: selectedTheme) { _, newTheme in
                UserDefaults.standard.set(newTheme.rawValue, forKey: "wavebar.selectedTheme")
            }
            .onChange(of: liquidIntensity) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: "wavebar.liquidIntensity")
            }
            .onChange(of: hideBorderAndShadow) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: "wavebar.hideBorderAndShadow")
            }
        }
        .frame(minWidth: 160, minHeight: 30)
        .ignoresSafeArea()
    }
    
    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Audio Input Selector
            VStack(alignment: .leading, spacing: 5) {
                Text("AUDIO INPUT")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.gray)
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.caption)
                        .foregroundColor(.teal)
                        .frame(width: 16)
                    Picker("", selection: Binding(
                        get: { audioEngineManager.selectedDeviceID ?? 0 },
                        set: { newID in
                            if newID != 0 {
                                audioEngineManager.start(deviceID: newID)
                                spectrumAnalyzer.updateSampleRate(audioEngineManager.sampleRate)
                            }
                        }
                    )) {
                        Text("Select Input Device...").tag(UInt32(0))
                        ForEach(audioEngineManager.devices, id: \.id) { dev in
                            Text(dev.name).tag(dev.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
            
            // Color Theme Selector
            VStack(alignment: .leading, spacing: 5) {
                Text("COLOR THEME")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.gray)
                HStack(spacing: 8) {
                    Image(systemName: "paintpalette.fill")
                        .font(.caption)
                        .foregroundColor(.teal)
                        .frame(width: 16)
                    Picker("", selection: $selectedTheme) {
                        ForEach(VisualizerTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
            
            Divider()
            
            settingsSlider(
                title: "SENSITIVITY",
                icon: "slider.horizontal.3",
                value: $spectrumAnalyzer.sensitivity,
                range: 0.3...3.0
            )
            
            settingsSlider(
                title: "DECAY SMOOTH",
                icon: "waveform.path",
                value: $spectrumAnalyzer.smoothness,
                range: 0.03...0.30
            )
            
            VStack(alignment: .leading, spacing: 5) {
                Text("BARS")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.gray)
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar")
                        .font(.caption)
                        .foregroundColor(.teal)
                        .frame(width: 16)
                    Slider(value: Binding(
                        get: { Double(spectrumAnalyzer.bucketCount) },
                        set: { spectrumAnalyzer.bucketCount = Int($0) }
                    ), in: 24...160, step: 4)
                    Text("\(spectrumAnalyzer.bucketCount)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.65))
                        .frame(width: 28, alignment: .trailing)
                }
            }
            
            HStack(spacing: 16) {
                Toggle("LOW EQ", isOn: $spectrumAnalyzer.lowBoostEnabled)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11, weight: .semibold))
                
                Toggle("VOLUME LINK", isOn: Binding(
                    get: { volumeLinkManager.isEnabled },
                    set: { newValue in
                        if newValue {
                            if volumeLinkManager.checkAccessibility(prompt: true) {
                                volumeLinkManager.isEnabled = true
                            } else {
                                volumeLinkManager.isEnabled = false
                                volumeLinkManager.openAccessibilitySettings()
                            }
                        } else {
                            volumeLinkManager.isEnabled = false
                        }
                    }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 11, weight: .semibold))
            }
            
            Toggle("DESKTOP BLEND MODE", isOn: $hideBorderAndShadow)
                .toggleStyle(.checkbox)
                .font(.system(size: 11, weight: .semibold))
            
            settingsSlider(
                title: "LIQUID FX",
                icon: "drop.fill",
                value: $liquidIntensity,
                range: 0.0...1.0
            )
            
            settingsSlider(
                title: "BASS LIMIT",
                icon: "arrow.down.forward.and.arrow.up.backward",
                value: $spectrumAnalyzer.fMin,
                range: 20...1000
            )
            
            settingsSlider(
                title: "TREBLE LIMIT",
                icon: "arrow.up.forward.and.arrow.down.backward",
                value: $spectrumAnalyzer.fMax,
                range: 1000...22000
            )
        }
        .padding(16)
        .frame(width: 300)
    }
    
    private func settingsSlider<V: BinaryFloatingPoint>(
        title: String,
        icon: String,
        value: Binding<V>,
        range: ClosedRange<V>
    ) -> some View where V.Stride: BinaryFloatingPoint {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.gray)
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.teal)
                    .frame(width: 16)
                Slider(value: value, in: range)
            }
        }
    }
    
    
}

// Clean custom colors extension to fit sleek aesthetics
extension Color {
    static let amberPrimary = Color(red: 1.0, green: 0.65, blue: 0.15)
    
    /// Blends two colors together with a weight between 0.0 and 1.0.
    func blend(with other: Color, weight: Double) -> Color {
        let c1 = NSColor(self)
        let c2 = NSColor(other)
        guard let blended = c1.blended(withFraction: CGFloat(weight), of: c2) else {
            return self
        }
        return Color(blended)
    }
}

/// A DisplayLink timer synchronized exactly with the hardware refresh rate of the monitor (VSYNC).
/// Supports ProMotion 120Hz/144Hz displays with zero jitter.
public final class DisplayLinkAction: NSObject {
    private var displayLink: CADisplayLink?
    private let action: () -> Void
    
    public init(action: @escaping () -> Void) {
        self.action = action
        super.init()
        
        // Start the display link targeting the main thread common runloop mode on macOS
        let link = NSScreen.main?.displayLink(target: self, selector: #selector(tick))
            ?? NSScreen.screens.first?.displayLink(target: self, selector: #selector(tick))
        link?.add(to: RunLoop.main, forMode: RunLoop.Mode.common)
        self.displayLink = link
    }
    
    @objc private func tick() {
        action()
    }
    
    public func invalidate() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    deinit {
        invalidate()
    }
}
