import SwiftUI
import AVFoundation
import CoreAudio

/// Pre-allocated scratch buffers to prevent 60 FPS garbage collection pressure.
private final class DSPBufferHolder {
    var sampleBuffer: [Float]
    var magnitudes: [Float]
    
    init(fftSize: Int) {
        self.sampleBuffer = [Float](repeating: 0.0, count: fftSize)
        self.magnitudes = [Float](repeating: 0.0, count: fftSize / 2)
    }
}

public enum VisualizerTheme: String, CaseIterable, Identifiable {
    case aurora = "Aurora"      // Deep Indigo -> Teal -> Cyan -> Mint White
    case midnight = "Midnight"  // Indigo -> Violet -> Magenta -> Pink
    case copper = "Sunset"      // Burgundy -> Crimson -> Amber -> Gold
    case monochrome = "Silver"  // Graphite -> Slate -> Silver -> White
    
    public var id: String { self.rawValue }
    
    public var colors: [Color] {
        switch self {
        case .aurora:
            return [
                Color(red: 0.05, green: 0.35, blue: 0.55).opacity(0.85),
                Color(red: 0.0, green: 0.75, blue: 0.70),
                Color(red: 0.0, green: 0.9, blue: 0.85),
                Color(red: 0.8, green: 1.0, blue: 0.9)
            ]
        case .midnight:
            return [
                Color(red: 0.15, green: 0.05, blue: 0.45).opacity(0.85),
                Color(red: 0.35, green: 0.1, blue: 0.75),
                Color(red: 0.65, green: 0.2, blue: 0.85),
                Color(red: 0.95, green: 0.6, blue: 0.85)
            ]
        case .copper:
            return [
                Color(red: 0.35, green: 0.05, blue: 0.15).opacity(0.85),
                Color(red: 0.7, green: 0.15, blue: 0.15),
                Color(red: 0.95, green: 0.45, blue: 0.15),
                Color(red: 1.0, green: 0.85, blue: 0.5)
            ]
        case .monochrome:
            return [
                Color(red: 0.15, green: 0.18, blue: 0.22).opacity(0.85),
                Color(red: 0.35, green: 0.38, blue: 0.42),
                Color(red: 0.65, green: 0.68, blue: 0.72),
                Color(red: 0.95, green: 0.97, blue: 1.0)
            ]
        }
    }
    
    public var glowColor: Color {
        switch self {
        case .aurora:
            return Color.teal
        case .midnight:
            return Color.purple
        case .copper:
            return Color.orange
        case .monochrome:
            return Color(red: 0.4, green: 0.5, blue: 0.6)
        }
    }
}

public struct MainView: View {
    @ObservedObject var audioEngineManager: AudioEngineManager
    @ObservedObject var spectrumAnalyzer: SpectrumAnalyzer
    let ringBuffer: AudioRingBuffer
    let fftProcessor: FFTProcessor
    
    @State private var bufferHolder: DSPBufferHolder
    @State private var showControls: Bool = true
    @State private var selectedTheme: VisualizerTheme = .aurora
    
    // High-frequency publisher timer to drive real-time analysis at 60 FPS
    private let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()
    
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
        ZStack {
            // 1. Rich Deep-Space Background
            Color(red: 0.03, green: 0.03, blue: 0.05)
                .edgesIgnoringSafeArea(.all)
            
            // 2. Beat-Driven Radial Glow Backdrop
            let glowVal = spectrumAnalyzer.pulseGlow
            RadialGradient(
                gradient: Gradient(colors: [
                    selectedTheme.glowColor.opacity(Double(glowVal) * 0.35),
                    selectedTheme.glowColor.opacity(Double(glowVal) * 0.1),
                    Color.clear
                ]),
                center: .bottom,
                startRadius: 0,
                endRadius: 350
            )
            .blendMode(.screen)
            .edgesIgnoringSafeArea(.all)
            .animation(.easeOut(duration: 0.1), value: glowVal)
            
            // 3. Hardware-Accelerated Spectrum Canvas (Driven reactively by @Published smoothedHeights)
            Canvas { context, size in
                let heights = spectrumAnalyzer.smoothedHeights
                // let peaks = spectrumAnalyzer.peakHeights
                let count = heights.count
                guard count > 0 else { return }
                
                let spacing: CGFloat = 2.5
                let totalSpacing = spacing * CGFloat(count - 1)
                let barWidth = max(1.0, (size.width - totalSpacing) / CGFloat(count))
                
                // Beat-driven overall canvas resonant vertical scaling (adds up to 8% vertical expansion on strong beats)
                let pulseScale = 1.0 + CGFloat(spectrumAnalyzer.pulseGlow) * 0.08
                
                // Top Y coordinate of the stationary gradient (top of maximum possible bar height)
                let gradientTopY = size.height - 10 - (size.height - 45) * 1.08
                
                for i in 0..<count {
                    let valFraction = CGFloat(heights[i])
                    // Scale bars using dynamic pulse scale
                    let barHeight = max(1.5, valFraction * (size.height - 45) * pulseScale)
                    
                    let x = CGFloat(i) * (barWidth + spacing)
                    let y = size.height - barHeight - 10
                    
                    let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                    let roundedPath = Path(roundedRect: rect, cornerRadius: min(barWidth / 2, 3))
                    
                    // Vertical Color Gradient (globally aligned horizontally to prevent dizzying stretching)
                    let barGradient = Gradient(colors: selectedTheme.colors)
                    
                    context.fill(
                        roundedPath,
                        with: .linearGradient(
                            barGradient,
                            startPoint: CGPoint(x: x + barWidth / 2, y: size.height - 10),
                            endPoint: CGPoint(x: x + barWidth / 2, y: gradientTopY)
                        )
                    )
                    
                    // --- Draw Floating Peak Dot (with Gravity Physics) ---
                    // Temporarily commented out to prevent visual afterimage/persistence discomfort on dark backgrounds
                    /*
                    if i < peaks.count {
                        let peakFraction = CGFloat(peaks[i])
                        let peakHeight = peakFraction * (size.height - 45) * pulseScale
                        let peakY = size.height - peakHeight - 10
                        
                        // Render a floating horizontal bar at peak height
                        let peakRect = CGRect(x: x, y: peakY - 3, width: barWidth, height: 2)
                        let peakPath = Path(roundedRect: peakRect, cornerRadius: 1)
                        context.fill(peakPath, with: .color(Color.white.opacity(0.75)))
                    }
                    */
                }
            }
            .edgesIgnoringSafeArea(.horizontal)
            
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
                if showControls {
                    HStack(spacing: 16) {
                        // Device Selector
                        VStack(alignment: .leading, spacing: 4) {
                            Text("AUDIO INPUT")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.gray)
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
                            .frame(width: 140)
                        }
                        
                        Divider().frame(height: 24)
                        
                        // Theme Selector
                        VStack(alignment: .leading, spacing: 4) {
                            Text("COLOR THEME")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.gray)
                            Picker("", selection: $selectedTheme) {
                                ForEach(VisualizerTheme.allCases) { theme in
                                    Text(theme.rawValue).tag(theme)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 100)
                        }
                        
                        Divider().frame(height: 24)
                        
                        // Sensitivity
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SENSITIVITY")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.gray)
                            HStack {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.caption)
                                    .foregroundColor(.teal)
                                Slider(value: $spectrumAnalyzer.sensitivity, in: 0.3...3.0)
                                    .frame(width: 70)
                            }
                        }
                        
                        Divider().frame(height: 24)
                        
                        // Smoothness (Release)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("DECAY SMOOTH")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.gray)
                            HStack {
                                Image(systemName: "waveform.path")
                                    .font(.caption)
                                    .foregroundColor(.teal)
                                Slider(value: $spectrumAnalyzer.smoothness, in: 0.03...0.30)
                                    .frame(width: 70)
                            }
                        }
                        
                        Divider().frame(height: 24)
                        
                        // Bar count
                        VStack(alignment: .leading, spacing: 4) {
                            Text("BARS")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.gray)
                            HStack {
                                Image(systemName: "chart.bar")
                                    .font(.caption)
                                    .foregroundColor(.teal)
                                Slider(value: Binding(
                                    get: { Double(spectrumAnalyzer.bucketCount) },
                                    set: { spectrumAnalyzer.bucketCount = Int($0) }
                                ), in: 24...96, step: 4)
                                    .frame(width: 70)
                            }
                        }
                        
                        Divider().frame(height: 24)
                        
                        // EQ Boost Toggle
                        VStack(alignment: .leading, spacing: 4) {
                            Text("LOW EQ")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.gray)
                            Toggle("Boost Bass", isOn: $spectrumAnalyzer.lowBoostEnabled)
                                .toggleStyle(.checkbox)
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal, 16)
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
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.3)) {
                showControls = inside
            }
        }
        .onReceive(timer) { _ in
            // Execute real-time audio DSP calculations at 60 FPS on the main thread
            let fftSize = fftProcessor.fftSize
            spectrumAnalyzer.updateSampleRate(audioEngineManager.sampleRate)
            
            // A. Read latest audio frames
            ringBuffer.readLatest(count: fftSize, into: &bufferHolder.sampleBuffer)
            
            // B. Run FFT analysis
            fftProcessor.analyze(samples: bufferHolder.sampleBuffer, magnitudes: &bufferHolder.magnitudes)
            
            // C. Feed spectral results to dynamic smoothing and shaping
            spectrumAnalyzer.processFrame(magnitudes: bufferHolder.magnitudes)
        }
        .frame(minWidth: 640, minHeight: 400)
    }
}

// Clean custom colors extension to fit sleek aesthetics
extension Color {
    static let amberPrimary = Color(red: 1.0, green: 0.65, blue: 0.15)
}
