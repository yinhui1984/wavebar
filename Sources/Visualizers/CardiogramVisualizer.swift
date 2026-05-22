import SwiftUI

public struct CardiogramVisualizer: View {
    let heights: [Float]
    let blendedColors: [Color]
    let pulseGlow: Float
    let time: Double
    let cardiogramSpeed: Double
    let cardiogramGridIntensity: Double
    let cardiogramLineThickness: Double
    let cardiogramAmplitude: Double
    let cardiogramJitter: Double
    let cardiogramShowHUD: Bool
    
    public init(
        heights: [Float],
        blendedColors: [Color],
        pulseGlow: Float,
        time: Double,
        cardiogramSpeed: Double = 1.0,
        cardiogramGridIntensity: Double = 0.4,
        cardiogramLineThickness: Double = 1.0,
        cardiogramAmplitude: Double = 1.0,
        cardiogramJitter: Double = 1.0,
        cardiogramShowHUD: Bool = true
    ) {
        self.heights = heights
        self.blendedColors = blendedColors
        self.pulseGlow = pulseGlow
        self.time = time
        self.cardiogramSpeed = cardiogramSpeed
        self.cardiogramGridIntensity = cardiogramGridIntensity
        self.cardiogramLineThickness = cardiogramLineThickness
        self.cardiogramAmplitude = cardiogramAmplitude
        self.cardiogramJitter = cardiogramJitter
        self.cardiogramShowHUD = cardiogramShowHUD
    }
    
    public var body: some View {
        Canvas { context, size in
            let count = heights.count
            guard count > 0 else { return }
            
            // 1. Multi-spectral real-time audio bands analysis
            let bassVal: CGFloat = {
                let maxIndex = min(count - 1, Int(CGFloat(count) * 0.15))
                guard maxIndex >= 0 else { return 0.0 }
                let sum = heights[0...maxIndex].reduce(0, +)
                return CGFloat(sum / Float(maxIndex + 1))
            }()
            
            let midVal: CGFloat = {
                let minIndex = min(count - 1, Int(CGFloat(count) * 0.15))
                let maxIndex = min(count - 1, Int(CGFloat(count) * 0.60))
                guard maxIndex > minIndex else { return 0.0 }
                let sum = heights[minIndex...maxIndex].reduce(0, +)
                return CGFloat(sum / Float(maxIndex - minIndex + 1))
            }()
            
            let trebleVal: CGFloat = {
                let minIndex = min(count - 1, Int(CGFloat(count) * 0.60))
                let maxIndex = count - 1
                guard maxIndex > minIndex else { return 0.0 }
                let sum = heights[minIndex...maxIndex].reduce(0, +)
                return CGFloat(sum / Float(maxIndex - minIndex + 1))
            }()
            
            // Theme colors
            let themeColor = blendedColors.first ?? .teal
            
            // 2. Draw modern high-tech medical grid backdrop
            if cardiogramGridIntensity > 0.001 {
                drawGrid(context: context, size: size, opacity: cardiogramGridIntensity)
            }
            
            // 3. Draw the dynamic audio-driven spectrum waveform
            drawCardiogramWave(
                context: context,
                size: size,
                bass: bassVal,
                mid: midVal,
                treble: trebleVal,
                pulse: CGFloat(pulseGlow)
            )
            
            // 4. Draw modern medical HUD overlays (only if size is large enough to prevent clutter and enabled)
            if size.height >= 40 && cardiogramShowHUD {
                drawHUD(context: context, size: size, themeColor: themeColor, pulse: CGFloat(pulseGlow))
            }
        }
    }
    
    /// Renders standard ECG graph paper major & minor grids matching medical monitors.
    private func drawGrid(context: GraphicsContext, size: CGSize, opacity: Double) {
        let themeColor = blendedColors.first ?? .teal
        let gridColor = themeColor.opacity(0.08 * opacity)
        
        let isSmall = size.height < 100
        let minorSpacing: CGFloat = isSmall ? 6.0 : 10.0
        let majorSpacing: CGFloat = minorSpacing * 5.0
        
        // A. Minor grid lines (fine 1mm style)
        var minorPath = Path()
        
        var x: CGFloat = 0
        while x < size.width {
            minorPath.move(to: CGPoint(x: x, y: 0))
            minorPath.addLine(to: CGPoint(x: x, y: size.height))
            x += minorSpacing
        }
        
        var y: CGFloat = 0
        while y < size.height {
            minorPath.move(to: CGPoint(x: 0, y: y))
            minorPath.addLine(to: CGPoint(x: size.width, y: y))
            y += minorSpacing
        }
        
        context.stroke(minorPath, with: .color(gridColor.opacity(0.35)), lineWidth: 0.5)
        
        // B. Major grid lines (thick 5mm style)
        var majorPath = Path()
        
        x = 0
        while x < size.width {
            majorPath.move(to: CGPoint(x: x, y: 0))
            majorPath.addLine(to: CGPoint(x: x, y: size.height))
            x += majorSpacing
        }
        
        y = 0
        while y < size.height {
            majorPath.move(to: CGPoint(x: 0, y: y))
            majorPath.addLine(to: CGPoint(x: size.width, y: y))
            y += majorSpacing
        }
        
        context.stroke(majorPath, with: .color(gridColor), lineWidth: 0.9)
    }
    
    /// Renders a highly responsive, symmetric audio-driven cardiogram waveform.
    private func drawCardiogramWave(
        context: GraphicsContext,
        size: CGSize,
        bass: CGFloat,
        mid: CGFloat,
        treble: CGFloat,
        pulse: CGFloat
    ) {
        let cy = size.height / 2
        let count = heights.count
        
        // Speed scaling and physical continuous phase
        let t = CGFloat(time) * 12.0 * CGFloat(cardiogramSpeed)
        
        var path = Path()
        var glowPath = Path()
        var started = false
        
        let stepX: CGFloat = 1.5 // Spline curve resolution
        let maxWaveHeight = ((size.height * 0.40) + pulse * (size.height * 0.12)) * CGFloat(cardiogramAmplitude)
        
        // We modulate the oscillating carrier frequency by the beat (pulse) intensity
        let carrierFreq = 16.0 + pulse * 10.0
        
        for x in stride(from: CGFloat(0), to: size.width, by: stepX) {
            let normalizedX = x / size.width
            
            // Symmetrical mapping: center of screen (0.5) is Bass, edges (0.0 and 1.0) are Treble
            let distFromCenter = abs(normalizedX - 0.5) * 2.0 // 0.0 in center, 1.0 at left/right edges
            
            // Map distance to spectrum indices
            let freqIndex = max(0, min(Int(distFromCenter * CGFloat(count - 1)), count - 1))
            let frequencyVal = CGFloat(heights[freqIndex])
            
            // Smooth window function: tapers wave to exactly 0 at the left and right boundaries
            let window = pow(sin(normalizedX * .pi), 2.2)
            
            // Carrier wave to oscillate the frequency heights into a true waveform look
            let carrier = sin(normalizedX * carrierFreq * .pi - t * 0.8)
            
            // Calculate primary spectrum-driven height
            var yOffset = frequencyVal * maxWaveHeight * window * carrier
            
            // Add subtle high-frequency electronic noise (organic medical screen baseline jitter)
            let baseNoise = sin(normalizedX * 160.0 + t * 2.5) * (0.3 + treble * 1.5) * (1.0 - window * 0.6) * CGFloat(cardiogramJitter)
            yOffset += baseNoise
            
            // Dynamic breathing motion (drifting baseline) driven by slow bass wave
            yOffset += cos(normalizedX * 4.0 - t * 0.25) * (0.2 + bass * 0.5)
            
            let y = cy - yOffset
            let point = CGPoint(x: x, y: y)
            
            if !started {
                path.move(to: point)
                glowPath.move(to: point)
                started = true
            } else {
                path.addLine(to: point)
                glowPath.addLine(to: point)
            }
        }
        
        let startColor = blendedColors.first ?? .teal
        let endColor = blendedColors.last ?? .cyan
        
        // A. Draw wide outer neon glow
        let auraGradient = Gradient(colors: [startColor.opacity(0.12), endColor.opacity(0.20), startColor.opacity(0.12)])
        context.stroke(
            glowPath,
            with: .linearGradient(
                auraGradient,
                startPoint: CGPoint(x: 0, y: cy),
                endPoint: CGPoint(x: size.width, y: cy)
            ),
            lineWidth: (size.height < 100 ? 4.5 : 6.5) * CGFloat(cardiogramLineThickness)
        )
        
        // B. Draw active tracer line
        let traceGradient = Gradient(colors: [startColor.opacity(0.68), endColor.opacity(0.88), startColor.opacity(0.68)])
        context.stroke(
            path,
            with: .linearGradient(
                traceGradient,
                startPoint: CGPoint(x: 0, y: cy),
                endPoint: CGPoint(x: size.width, y: cy)
            ),
            lineWidth: (size.height < 100 ? 1.8 : 2.5) * CGFloat(cardiogramLineThickness)
        )
        
        // C. Draw intense white hot core trace
        context.stroke(
            path,
            with: .color(.white.opacity(0.92)),
            lineWidth: (size.height < 100 ? 0.7 : 1.0) * CGFloat(cardiogramLineThickness)
        )
    }
    
    /// Renders dynamic medical HUD info overlays inside the monitor.
    private func drawHUD(context: GraphicsContext, size: CGSize, themeColor: Color, pulse: CGFloat) {
        // Calculate dynamic organic BPM based on real-time beat pulse
        let bpm = Int(72 + pulse * 36 + sin(time * 0.4) * 2)
        
        // A. Left Side: PULSE ACTIVE indicator
        let leftText = Text("PULSE ACTIVE")
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundColor(themeColor.opacity(0.6))
        
        context.draw(leftText, at: CGPoint(x: 45, y: 15), anchor: .leading)
        
        // B. Right Side: HR BPM + beating glowing heart icon
        let bpmText = Text("HR \(bpm) BPM ")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(themeColor)
        
        let heartSize = CGFloat(8 + pulse * 4)
        let heartText = Text("♥")
            .font(.system(size: heartSize))
            .foregroundColor(Color.red.opacity(Double(0.4 + pulse * 0.6)))
        
        // Draw the combined HR text & beating heart
        context.draw(bpmText + heartText, at: CGPoint(x: size.width - 45, y: 15), anchor: .trailing)
    }
}
