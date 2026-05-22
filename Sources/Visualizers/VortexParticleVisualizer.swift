import SwiftUI

public struct VortexParticleVisualizer: View {
    let heights: [Float]
    let blendedColors: [Color]
    let pulseGlow: Float
    let time: Double
    
    public init(heights: [Float], blendedColors: [Color], pulseGlow: Float, time: Double) {
        self.heights = heights
        self.blendedColors = blendedColors
        self.pulseGlow = pulseGlow
        self.time = time
    }
    
    public var body: some View {
        Canvas { context, size in
            let count = heights.count
            guard count > 0 else { return }
            
            // --- 3D SILKY WINGTIP VORTEX STREAM GRAPHICS ---
            let numStreams = 8
            let beatGlow = CGFloat(pulseGlow)
            let t = CGFloat(time)
            let centerY = size.height * 0.52
            
            let fract = { (val: CGFloat) -> CGFloat in
                val - floor(val)
            }
            
            // Dynamic 3D Projection Closure with explicit signature for fast compilation
            let projectPoint: (Int, CGFloat) -> (CGPoint, CGFloat, CGFloat, Double) = { s, u in
                let isLeft = (s % 2 == 0)
                let systemCenterX: CGFloat = isLeft ? (size.width * 0.24) : (size.width * 0.76)
                let swirlDir: CGFloat = isLeft ? 1.0 : -1.0
                
                let depthFraction: CGFloat = CGFloat(s) / CGFloat(numStreams - 1)
                
                // Stream classification within left/right system (0 to 3)
                let systemIndex = s / 2
                let systemFraction: CGFloat = CGFloat(systemIndex) / 3.0 // 0.0 to 1.0
                
                // 3D Camera Projection
                let cameraZ: CGFloat = 180.0
                let fov: CGFloat = 280.0
                let pz: CGFloat = cameraZ + (1.0 - depthFraction) * 160.0
                let perspectiveScale: CGFloat = fov / pz
                
                // Map u to audio spectrum index
                let spectrumIndex = Int(round(u * CGFloat(count - 1)))
                let audioVal: CGFloat = CGFloat(heights[max(0, min(spectrumIndex, count - 1))])
                
                // Core filaments swirl faster and are tighter. Outer wake swirls slower and wider.
                let isCore = (systemIndex == 0)
                let swirlFreq: CGFloat = isCore ? 7.0 : (4.5 - systemFraction * 1.5)
                let swirlSpeed: CGFloat = isCore ? 4.5 : (2.8 - systemFraction * 1.0)
                let angle: CGFloat = swirlDir * (u * 3.14159 * swirlFreq - t * swirlSpeed + depthFraction * 1.2)
                
                // Spiral radius: starts extremely tight at the edges (wingtips), expands downstream in the central wake
                let baseRadius: CGFloat = isCore ? (2.0 + depthFraction * 4.0) * (0.3 + u * 0.7) : (16.0 + systemFraction * 20.0) * (0.4 + u * 0.6)
                let audioRadius: CGFloat = audioVal * (isCore ? (6.0 + beatGlow * 8.0) : (15.0 + beatGlow * 20.0)) * sin(u * 3.14159)
                let spiralRadius: CGFloat = (baseRadius + audioRadius)
                
                let spiralX: CGFloat = cos(angle) * spiralRadius
                let spiralY: CGFloat = sin(angle) * spiralRadius * 0.58 // flat aspect ratio
                
                // Undulating breeze wave along the streamline
                let rippleFreq: CGFloat = 3.0 + systemFraction * 2.0
                let rippleSpeed: CGFloat = 1.6 + systemFraction * 0.8
                let rippleWave: CGFloat = sin(u * rippleFreq + t * rippleSpeed) * (5.0 + audioVal * 12.0)
                
                // Aerodynamic shedding flow: start from outer wingtips (edges) and flow inward to center wake
                let startX: CGFloat = isLeft ? 0.0 : size.width
                let endX: CGFloat = size.width * 0.5
                let baseX: CGFloat = startX + (endX - startX) * u
                
                let px3d: CGFloat = (baseX - systemCenterX) + spiralX
                let py3d: CGFloat = rippleWave + spiralY + (audioVal * 28.0 * (1.25 - systemFraction * 0.45))
                
                let screenX: CGFloat = systemCenterX + px3d * perspectiveScale
                let baselineY: CGFloat = centerY + (depthFraction - 0.5) * (size.height * 0.22)
                let screenY: CGFloat = baselineY - py3d * perspectiveScale
                
                // Depth and distance-modulated opacity
                let opacityScale: Double = Double(0.25 + depthFraction * 0.75) * (1.0 - Double(u) * 0.60)
                let audioOpacity: Double = Double(0.35 + audioVal * 1.5)
                let opacity: Double = min(1.0, opacityScale * audioOpacity)
                
                return (CGPoint(x: screenX, y: screenY), audioVal, perspectiveScale, opacity)
            }
            
            // 1. Draw continuous silky ribbons using quadratic Bezier interpolation
            for s in 0..<numStreams {
                let isLeft = (s % 2 == 0)
                let systemIndex = s / 2
                let isCore = (systemIndex == 0)
                let depthFraction = CGFloat(s) / CGFloat(numStreams - 1)
                
                let numSteps = 55
                var streamPath = Path()
                var started = false
                
                for c in 0..<numSteps {
                    let u = CGFloat(c) / CGFloat(numSteps - 1)
                    let (pt, _, _, _) = projectPoint(s, u)
                    guard pt.x.isFinite && pt.y.isFinite else { continue }
                    
                    if !started {
                        streamPath.move(to: pt)
                        started = true
                    } else {
                        let prevU = CGFloat(c - 1) / CGFloat(numSteps - 1)
                        let (prevPt, _, _, _) = projectPoint(s, prevU)
                        let midPt = CGPoint(x: (prevPt.x + pt.x)/2, y: (prevPt.y + pt.y)/2)
                        streamPath.addQuadCurve(to: midPt, control: prevPt)
                    }
                }
                
                // Ribbon styling: extremely soft, glowing, and flowing
                let baseLineOpacity = isCore ? (0.28 + depthFraction * 0.35) : (0.06 + depthFraction * 0.16)
                let lineOpacity = baseLineOpacity * (1.0 + Double(beatGlow) * 0.3)
                let lineColors = blendedColors.map { $0.opacity(lineOpacity) }
                let lineWidth = isCore ? max(1.0, 2.0 * depthFraction) : max(0.4, 0.8 * depthFraction)
                
                context.stroke(
                    streamPath,
                    with: .linearGradient(
                        Gradient(colors: lineColors),
                        startPoint: isLeft ? CGPoint(x: 0, y: 0) : CGPoint(x: size.width, y: 0),
                        endPoint: isLeft ? CGPoint(x: size.width * 0.5, y: 0) : CGPoint(x: size.width * 0.5, y: 0)
                    ),
                    lineWidth: lineWidth
                )
                
                // Glow core filament for the main wingtip vortex center
                if isCore {
                    let coreGlowOpacity = 0.45 * (1.0 + Double(beatGlow) * 0.4)
                    let coreColor = Color.white.opacity(coreGlowOpacity)
                    context.stroke(
                        streamPath,
                        with: .color(coreColor),
                        lineWidth: max(0.5, 0.8 * depthFraction)
                    )
                }
            }
            
            // 2. Draw continuous fluid vortex particles flowing along the streamlines
            let numParticles = 12
            for s in 0..<numStreams {
                let systemIndex = s / 2
                let isCore = (systemIndex == 0)
                let depthFraction = CGFloat(s) / CGFloat(numStreams - 1)
                
                for p in 0..<numParticles {
                    // Flowing position u: slides smoothly from 0 to 1 over time
                    let flowSpeed: CGFloat = isCore ? 0.12 : 0.08
                    let baseU = CGFloat(p) / CGFloat(numParticles)
                    let u = fract(baseU + t * flowSpeed)
                    
                    let (pt, audioVal, perspectiveScale, opacity) = projectPoint(s, u)
                    guard pt.x.isFinite && pt.y.isFinite else { continue }
                    
                    // Particle size: core particles are tiny and dense; outer particles are larger and softer
                    let basePSize = isCore ? (2.0 + depthFraction * 2.5) : (4.0 + depthFraction * 6.5)
                    let pSize = basePSize * perspectiveScale * 0.65 * (0.35 + audioVal * 0.8)
                    
                    // Edge fade out near start and end to prevent popping at wingtip or wake boundaries
                    let edgeFade: Double = {
                        if u < 0.08 {
                            return Double(u / 0.08)
                        } else if u > 0.85 {
                            return Double((1.0 - u) / 0.15)
                        } else {
                            return 1.0
                        }
                    }()
                    
                    let finalOpacity = opacity * edgeFade
                    guard finalOpacity > 0.01 else { continue }
                    
                    // Color gradient matching the streamline coordinate
                    let colorIndex = u * CGFloat(blendedColors.count - 1)
                    let idxLower = Int(floor(colorIndex))
                    let idxUpper = Int(ceil(colorIndex))
                    let fractVal = colorIndex - CGFloat(idxLower)
                    let baseColor = blendedColors[max(0, min(idxLower, blendedColors.count - 1))].blend(
                        with: blendedColors[max(0, min(idxUpper, blendedColors.count - 1))],
                        weight: Double(fractVal)
                    )
                    
                    // Glowing color mapping
                    let blendWeight = isCore ? 0.65 : Double(0.1 + 0.4 * audioVal)
                    let particleColor = baseColor.blend(with: .white, weight: blendWeight)
                    
                    // Soft core particle
                    context.fill(
                        Path(ellipseIn: CGRect(x: pt.x - pSize/2, y: pt.y - pSize/2, width: pSize, height: pSize)),
                        with: .color(particleColor.opacity(finalOpacity * 0.85))
                    )
                    
                    // Soft glowing beat-driven halo
                    if audioVal > 0.25 || isCore {
                        let glowSize = pSize * (isCore ? 2.0 : 2.8)
                        let glowOpacity = finalOpacity * (isCore ? 0.25 : 0.15)
                        context.fill(
                            Path(ellipseIn: CGRect(x: pt.x - glowSize/2, y: pt.y - glowSize/2, width: glowSize, height: glowSize)),
                            with: .color(baseColor.opacity(glowOpacity))
                        )
                    }
                }
            }
        }
    }
}
