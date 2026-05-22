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


public enum VisualizerStyle: String, CaseIterable, Identifiable {
    case bars = "Frequency Bars"
    case particles = "3D Particle Flow"
    
    public var id: String { self.rawValue }
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
    @State private var selectedStyle: VisualizerStyle = {
        if let saved = UserDefaults.standard.string(forKey: "wavebar.selectedStyle"),
           let style = VisualizerStyle(rawValue: saved) {
            return style
        }
        return .bars
    }()
    @State private var time: Double = 0.0
    
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
    @State private var flowSpeedMultiplier: Double = {
        let saved = UserDefaults.standard.object(forKey: "wavebar.flowSpeedMultiplier") as? Double
        return saved ?? 1.0
    }()
    @State private var turbulenceStrength: Double = {
        let saved = UserDefaults.standard.object(forKey: "wavebar.turbulenceStrength") as? Double
        return saved ?? 1.0
    }()
    @State private var vortexSize: Double = {
        let saved = UserDefaults.standard.object(forKey: "wavebar.vortexSize") as? Double
        return saved ?? 1.0
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
            mainContent(geometry: geometry)
        }
        .frame(minWidth: 160, minHeight: 30)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func mainContent(geometry: GeometryProxy) -> some View {
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
        
        let baseColors = selectedTheme.colors
        let beatFlash = Double(glowVal)
        let blendedColors = baseColors.enumerated().map { index, color -> Color in
            let factor = baseColors.count > 1 ? Double(index) / Double(baseColors.count - 1) : 0.0
            let flashWeight = min(1.0, beatFlash * 0.65 * factor)
            return color.blend(with: .white, weight: flashWeight)
        }
        
        contentZStack(
            geometry: geometry,
            isCompact: isCompact,
            cornerRadius: cornerRadius,
            glowBlur: glowBlur,
            glowOpacity: glowOpacity,
            glowVal: glowVal,
            blendedColors: blendedColors
        )
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
            setupDisplayLink()
        }
        .onDisappear {
            displayLinkAction?.invalidate()
            displayLinkAction = nil
        }
    }

    @ViewBuilder
    private var statePersistenceObservers: some View {
        ZStack {
            Color.clear.onChange(of: selectedTheme) { _, newValue in
                UserDefaults.standard.set(newValue.rawValue, forKey: "wavebar.selectedTheme")
            }
            Color.clear.onChange(of: selectedStyle) { _, newValue in
                UserDefaults.standard.set(newValue.rawValue, forKey: "wavebar.selectedStyle")
            }
            Color.clear.onChange(of: liquidIntensity) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: "wavebar.liquidIntensity")
            }
            Color.clear.onChange(of: hideBorderAndShadow) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: "wavebar.hideBorderAndShadow")
            }
            Color.clear.onChange(of: flowSpeedMultiplier) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: "wavebar.flowSpeedMultiplier")
            }
            Color.clear.onChange(of: turbulenceStrength) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: "wavebar.turbulenceStrength")
            }
            Color.clear.onChange(of: vortexSize) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: "wavebar.vortexSize")
            }
        }
        .frame(width: 0, height: 0)
    }

    @ViewBuilder
    private func contentZStack(
        geometry: GeometryProxy,
        isCompact: Bool,
        cornerRadius: CGFloat,
        glowBlur: CGFloat,
        glowOpacity: Double,
        glowVal: Float,
        blendedColors: [Color]
    ) -> some View {
        ZStack {
            // 0. Invisible State Observers
            statePersistenceObservers
            
            // 1. Translucent Deep Space Glass Backdrop
            backdropSection(isCompact: isCompact)
            
            // 2. Inner Nebula Glow Backdrop
            nebulaGlowSection(glowBlur: glowBlur, glowOpacity: glowOpacity, glowVal: glowVal)
            
            // 3. Decoupled Visualizer View Router (Frequency Bars or 3D Vortex Flow)
            visualizerContainer(
                width: geometry.size.width,
                height: geometry.size.height,
                blendedColors: blendedColors
            )
            .offset(y: shakeOffset)
            .edgesIgnoringSafeArea(.horizontal)
            .contentShape(Rectangle())
            
            // 4. Input Failure Overlay Warning
            errorOverlaySection
            
            // 5. Floating Frosted Control Bar
            floatingControlBarSection
            
            // 6. Accent Border on top of content
            if !isCompact && !hideBorderAndShadow {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }

    private func setupDisplayLink() {
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
            
            // C. Update continuous time for visual animations (only if particles style is active to save overhead)
            if selectedStyle == .particles {
                self.time += 0.012 * selectedTheme.physicsResponsiveness
            }
        }
    }

    @ViewBuilder
    private func backdropSection(isCompact: Bool) -> some View {
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
    }

    @ViewBuilder
    private func nebulaGlowSection(glowBlur: CGFloat, glowOpacity: Double, glowVal: Float) -> some View {
        LinearGradient(
            gradient: Gradient(colors: selectedTheme.colors),
            startPoint: .leading,
            endPoint: .trailing
        )
        .blur(radius: glowBlur)
        .opacity(glowOpacity)
        .scaleEffect(1.0 + CGFloat(glowVal) * 0.05)
        .blendMode(.screen)
    }

    @ViewBuilder
    private var errorOverlaySection: some View {
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
    }

    @ViewBuilder
    private var floatingControlBarSection: some View {
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
    }
    
    @ViewBuilder
    private func visualizerContainer(width: CGFloat, height: CGFloat, blendedColors: [Color]) -> some View {
        let visualizer = Group {
            if selectedStyle == .bars {
                FrequencyBarsVisualizer(
                    heights: spectrumAnalyzer.smoothedHeights,
                    blendedColors: blendedColors,
                    pulseGlow: spectrumAnalyzer.pulseGlow
                )
            } else {
                VortexParticleVisualizer(
                    heights: spectrumAnalyzer.smoothedHeights,
                    blendedColors: blendedColors,
                    pulseGlow: spectrumAnalyzer.pulseGlow,
                    time: time,
                    flowSpeedMultiplier: flowSpeedMultiplier,
                    turbulenceStrength: turbulenceStrength,
                    vortexSize: vortexSize
                )
            }
        }
        
        visualizer
            .overlay {
                if liquidIntensity > 0.001 {
                    visualizer
                        .layerEffect(
                            ShaderLibrary.bundle(.module).liquidGelShader(
                                .float2(Float(width), Float(height)),
                                .float(Float(spectrumAnalyzer.pulseGlow)),
                                .float(Float(liquidIntensity))
                            ),
                            maxSampleOffset: CGSize(width: 8, height: 8)
                        )
                        .opacity(liquidIntensity)
                        .allowsHitTesting(false)
                }
            }
    }
    
    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            pickerSection
            
            Divider()
            
            slidersAndTogglesSection
        }
        .padding(16)
        .frame(width: 300)
    }
    
    private var pickerSection: some View {
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
            
            // Visualizer Style Selector
            VStack(alignment: .leading, spacing: 5) {
                Text("VISUALIZER STYLE")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.gray)
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.caption)
                        .foregroundColor(.teal)
                        .frame(width: 16)
                    Picker("", selection: $selectedStyle) {
                        ForEach(VisualizerStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
        }
    }
    
    private var slidersAndTogglesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
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
            
            if selectedStyle == .bars {
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
            } else {
                settingsSlider(
                    title: "PARTICLE SPEED",
                    icon: "speedometer",
                    value: $flowSpeedMultiplier,
                    range: 0.2...2.5
                )
                
                settingsSlider(
                    title: "TURBULENCE STRENGTH",
                    icon: "wind",
                    value: $turbulenceStrength,
                    range: 0.0...2.5
                )
                
                settingsSlider(
                    title: "VORTEX SIZE",
                    icon: "circle.dashed",
                    value: $vortexSize,
                    range: 0.3...2.0
                )
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
