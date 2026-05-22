import SwiftUI

public struct VortexParticleVisualizer: View {
    let heights: [Float]
    let blendedColors: [Color]
    let pulseGlow: Float
    let time: Double
    let flowSpeedMultiplier: Double
    let turbulenceStrength: Double
    let vortexSize: Double
    
    public init(
        heights: [Float],
        blendedColors: [Color],
        pulseGlow: Float,
        time: Double,
        flowSpeedMultiplier: Double = 1.0,
        turbulenceStrength: Double = 1.0,
        vortexSize: Double = 1.0
    ) {
        self.heights = heights
        self.blendedColors = blendedColors
        self.pulseGlow = pulseGlow
        self.time = time
        self.flowSpeedMultiplier = flowSpeedMultiplier
        self.turbulenceStrength = turbulenceStrength
        self.vortexSize = vortexSize
    }
    
    public var body: some View {
        Canvas { context, size in
            let count = heights.count
            guard count > 0 else { return }
            
            // ==========================================
            // 1. MULTI-SPECTRAL PHYSICAL REAL-TIME MAPPING
            // ==========================================
            let bassVal: CGFloat = {
                let maxIndex = min(count - 1, Int(CGFloat(count) * 0.12))
                guard maxIndex >= 0 else { return 0.0 }
                let sum = heights[0...maxIndex].reduce(0, +)
                return CGFloat(sum / Float(maxIndex + 1))
            }()
            
            let midVal: CGFloat = {
                let minIndex = min(count - 1, Int(CGFloat(count) * 0.12))
                let maxIndex = min(count - 1, Int(CGFloat(count) * 0.55))
                guard maxIndex > minIndex else { return 0.0 }
                let sum = heights[minIndex...maxIndex].reduce(0, +)
                return CGFloat(sum / Float(maxIndex - minIndex + 1))
            }()
            
            let trebleVal: CGFloat = {
                let minIndex = min(count - 1, Int(CGFloat(count) * 0.55))
                let maxIndex = count - 1
                guard maxIndex > minIndex else { return 0.0 }
                let sum = heights[minIndex...maxIndex].reduce(0, +)
                return CGFloat(sum / Float(maxIndex - minIndex + 1))
            }()
            
            let beatGlow = CGFloat(pulseGlow)
            let t = CGFloat(time)
            
            let fract = { (val: CGFloat) -> CGFloat in
                val - floor(val)
            }
            
            // ==========================================
            // 2. DETERMINISTIC FLUID TURBULENCE & FIELD NOISE (Zero Allocation)
            // ==========================================
            // Generates dynamic atmospheric turbulence coordinate shifts
            let getTurbulence = { (x: CGFloat, y: CGFloat, u: CGFloat) -> CGPoint in
                let timeScale = t * 2.5
                let tStrength = CGFloat(turbulenceStrength)
                let dx = sin(x * 0.04 + timeScale) * cos(y * 0.03 - u * 3.14) * (10.0 + trebleVal * 15.0) * tStrength
                let dy = cos(x * 0.035 - timeScale) * sin(y * 0.05 + u * 3.14) * (8.0 + bassVal * 20.0) * tStrength
                return CGPoint(x: dx, y: dy)
            }
            
            // ==========================================
            // 3. 3D ORBITAL CAMERA MODEL & PERSPECTIVE PROJECTION
            // ==========================================
            // Slowly orbiting 3D camera angles
            let cameraYaw = sin(t * 0.18) * 0.15 + midVal * 0.08
            let cameraPitch = cos(t * 0.12) * 0.12 - bassVal * 0.08
            let cameraRoll = t * 0.04
            
            let cosY = cos(cameraYaw)
            let sinY = sin(cameraYaw)
            let cosX = cos(cameraPitch)
            let sinX = sin(cameraPitch)
            let cosZ = cos(cameraRoll)
            let sinZ = sin(cameraRoll)
            
            // Deep space field parameters
            let fov: CGFloat = 300.0
            // Bass-driven camera warp (camera zooms into the vortex core on heavy beats!)
            let baseCameraZ: CGFloat = 220.0
            let dynamicCameraZ = baseCameraZ - (bassVal * 55.0 + beatGlow * 20.0)
            
            // Projection helper function taking a 3D coordinate and computing its screen projection
            // Returns: (screenPoint, audioValue, perspectiveScale, finalOpacity, gradientColor)
            let project3DPoint: (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) -> (CGPoint, CGFloat, CGFloat, Double, Color) = { px, py, pz, u, audioVal in
                // 1. 3D Camera Rotation around Center
                // Rotate Yaw (Y-axis)
                let rx1 = px * cosY - pz * sinY
                let rz1 = px * sinY + pz * cosY
                
                // Rotate Pitch (X-axis)
                let ry2 = py * cosX - rz1 * sinX
                let rz2 = py * sinX + rz1 * cosX
                
                // Rotate Roll (Z-axis)
                let rx3 = rx1 * cosZ - ry2 * sinZ
                let ry3 = rx1 * sinZ + ry2 * cosZ
                
                // Apply Dynamic Z Depth
                let finalZ = dynamicCameraZ + rz2
                let pScale = fov / max(15.0, finalZ)
                
                // 2. Project to 2D screen coordinate
                let screenX = size.width * 0.5 + rx3 * pScale
                let screenY = size.height * 0.52 - ry3 * pScale
                
                // 3. Multi-Spectral Temperature Chromatic Shift Color Selection
                // We shift color along the stream coordinate 'u'
                // At the start (wingtips, u=0): electric white/teal plasma
                // In the mid stream (u=0.5): hyper-violet/magenta
                // In the wake (u=1.0): cooling deep amber/crimson
                let numThemeColors = blendedColors.count
                let baseColor: Color = {
                    guard numThemeColors > 0 else { return .white }
                    if numThemeColors == 1 { return blendedColors[0] }
                    
                    let colPos = u * CGFloat(numThemeColors - 1)
                    let lowerIdx = max(0, min(Int(floor(colPos)), numThemeColors - 1))
                    let upperIdx = max(0, min(Int(ceil(colPos)), numThemeColors - 1))
                    let fractVal = colPos - CGFloat(lowerIdx)
                    
                    let col1 = blendedColors[lowerIdx]
                    let col2 = blendedColors[upperIdx]
                    return col1.blend(with: col2, weight: Double(fractVal))
                }()
                
                // Add a temperature hot core shift (blend white into the high energy centers)
                let energyFactor = Double(audioVal * 0.5 + trebleVal * 0.3)
                let colorTemp = baseColor.blend(with: .white, weight: min(0.85, energyFactor * (1.0 - Double(u) * 0.6)))
                
                // 4. Depth & Audio modulated opacity
                let opacityScale: Double = Double(0.25 + (1.0 - u) * 0.75) // fades out slightly as it drifts downstream
                let audioOpacity: Double = Double(0.4 + audioVal * 1.5)
                let finalOpacity = min(1.0, max(0.0, opacityScale * audioOpacity))
                
                return (CGPoint(x: screenX, y: screenY), audioVal, pScale, finalOpacity, colorTemp)
            }
            
            // ==========================================
            // 4. AERO-PLASMA VORTEX PHYSICAL SYSTEM SIMULATION
            // ==========================================
            let numSystems = 2 // Left (0) and Right (1) wingtips
            let numFilaments = 4 // Filaments per vortex (1 core + 3 sheaths)
            
            // Unified coordinate calculation helper to avoid duplicating math
            let getVortexCoords: (Int, Int, CGFloat) -> (px: CGFloat, py: CGFloat, pz: CGFloat, audioVal: CGFloat, isCore: Bool) = { sysIndex, filIndex, u in
                let isLeft = (sysIndex == 0)
                let swirlDir: CGFloat = isLeft ? 1.0 : -1.0
                
                let systemFraction = CGFloat(filIndex) / 3.0 // 0.0 (core) to 1.0 (outer sheath)
                let isCore = (filIndex == 0)
                
                // Fetch localized audio value matching position u
                let spectrumIdx = Int(round(u * CGFloat(count - 1)))
                let audioVal = CGFloat(heights[max(0, min(spectrumIdx, count - 1))])
                
                // Physical differential shear rate (Lamb-Oseen vortex core)
                let shearRate = 1.0 / (0.15 + systemFraction)
                let swirlFreq = (4.8 + shearRate * 0.6) * (1.0 + midVal * 0.45)
                let swirlSpeed = (3.2 + shearRate * 0.3) * (1.0 + bassVal * 0.35)
                
                // Helix swirling angle
                let angle = swirlDir * (u * 3.14159 * swirlFreq - t * swirlSpeed + systemFraction * 1.8)
                
                // Elliptical vortex sheath radius expanding downstream
                let baseRadius = isCore ? (2.0 + u * 6.0) : (14.0 + systemFraction * 22.0) * (0.35 + u * 0.65)
                let audioRadius = audioVal * (isCore ? (5.0 + beatGlow * 12.0) : (18.0 + beatGlow * 28.0)) * sin(u * 3.14159)
                let radius = (baseRadius + audioRadius) * CGFloat(vortexSize)
                
                let spiralY = sin(angle) * radius * 0.62
                let spiralZ = cos(angle) * radius * 0.62
                
                // Downstream X movement (flowing from outer tips to the wake center)
                let tipStartX = isLeft ? -size.width * 0.52 : size.width * 0.52
                let wakeEndX: CGFloat = 0.0
                let baseX = tipStartX + (wakeEndX - tipStartX) * u
                
                // Apply deterministic air turbulence coordinate perturbation
                let turb = getTurbulence(baseX, spiralY, u)
                
                var pyRaw = spiralY + turb.y + (audioVal * 28.0 * (1.2 - systemFraction * 0.45))
                var pzRaw = -120.0 + u * 240.0 + spiralZ + turb.x
                
                // Mutual Wake Braiding (Mutual roll-up after u > 0.65)
                if u > 0.65 {
                    let braidVal = (u - 0.65) / 0.35
                    // Both left and right wake elements wrap around each other
                    let braidAngle = t * 1.8 + (u - 0.65) * 3.14159 * 3.5
                    let braidRadius = (16.0 + bassVal * 12.0) * (1.0 - braidVal * 0.8) * CGFloat(vortexSize)
                    
                    let braidShiftY = sin(braidAngle) * braidRadius * 0.6
                    let braidShiftZ = cos(braidAngle) * braidRadius * 0.6 * swirlDir
                    
                    // Seamlessly interpolate into the mutual braided center spiral
                    pyRaw = (1.0 - braidVal) * pyRaw + braidVal * (pyRaw * 0.3 + braidShiftY)
                    pzRaw = (1.0 - braidVal) * pzRaw + braidVal * (pzRaw * 0.3 + braidShiftZ)
                }
                
                let pxRaw = baseX
                
                return (pxRaw, pyRaw, pzRaw, audioVal, isCore)
            }
            
            // ==========================================
            // PASS 1: AMBIENT ATMOSPHERIC STARDUST (BOKEH DUST)
            // ==========================================
            // Beautiful slow drifting dust particles swirling in the back to give galactic context
            let numDust = 32
            for i in 0..<numDust {
                let f = CGFloat(i) / CGFloat(numDust - 1)
                
                // Flow downstream coordinate
                let flowSpeed = (0.03 + sin(f * 9.0) * 0.015) * CGFloat(flowSpeedMultiplier)
                let u = fract(f + t * flowSpeed)
                
                // Position dust around left or right streams
                let isLeft = (i % 2 == 0)
                let swirlDir: CGFloat = isLeft ? 1.0 : -1.0
                
                let startX = isLeft ? -size.width * 0.55 : size.width * 0.55
                let endX: CGFloat = 0.0
                let x3d = startX + (endX - startX) * u
                
                // Gentle wide circular orbit around the vortex wakes
                let orbitRadius = (45.0 + fract(f * 7.0) * 80.0) * (1.0 + bassVal * 0.3)
                let orbitAngle = t * 0.6 * swirlDir + f * 6.28
                let y3d = sin(orbitAngle) * orbitRadius * 0.5
                let z3d = -150.0 + u * 300.0 + cos(orbitAngle) * orbitRadius
                
                // Project
                let (pt, _, pScale, opacity, baseColor) = project3DPoint(x3d, y3d, z3d, u, bassVal)
                guard pt.x.isFinite && pt.y.isFinite else { continue }
                
                // Edge fade out
                let edgeFade = u < 0.1 ? (u / 0.1) : (u > 0.85 ? (1.0 - u)/0.15 : 1.0)
                let finalOpacity = opacity * 0.06 * Double(edgeFade) * (0.6 + Double(bassVal) * 0.8)
                let dustSize = (25.0 + fract(f * 13.0) * 40.0) * pScale * 0.8 * (0.7 + beatGlow * 0.5)
                
                context.fill(
                    Path(ellipseIn: CGRect(x: pt.x - dustSize/2, y: pt.y - dustSize/2, width: dustSize, height: dustSize)),
                    with: .color(baseColor.opacity(finalOpacity))
                )
            }
            
            // ==========================================
            // PASS 2: SILKY PLASMA RIBBONS (STREAMLINES)
            // ==========================================
            for sys in 0..<numSystems {
                let isLeft = (sys == 0)
                for fil in 0..<numFilaments {
                    let isCore = (fil == 0)
                    let systemFraction = CGFloat(fil) / 3.0
                    
                    let numSteps = 55
                    var ribbonPath = Path()
                    var started = false
                    
                    for step in 0..<numSteps {
                        let u = CGFloat(step) / CGFloat(numSteps - 1)
                        let coords = getVortexCoords(sys, fil, u)
                        
                        let (pt, _, _, _, _) = project3DPoint(coords.px, coords.py, coords.pz, u, coords.audioVal)
                        guard pt.x.isFinite && pt.y.isFinite else { continue }
                        
                        if !started {
                            ribbonPath.move(to: pt)
                            started = true
                        } else {
                            let prevU = CGFloat(step - 1) / CGFloat(numSteps - 1)
                            let prevCoords = getVortexCoords(sys, fil, prevU)
                            let (prevPt, _, _, _, _) = project3DPoint(prevCoords.px, prevCoords.py, prevCoords.pz, prevU, prevCoords.audioVal)
                            
                            if prevPt.x.isFinite && prevPt.y.isFinite {
                                let midPt = CGPoint(x: (prevPt.x + pt.x) * 0.5, y: (prevPt.y + pt.y) * 0.5)
                                ribbonPath.addQuadCurve(to: midPt, control: prevPt)
                            }
                        }
                    }
                    
                    // Styled ribbon properties
                    let baseLineOpacity = isCore ? (0.28 + systemFraction * 0.22) : (0.05 + systemFraction * 0.12)
                    let ribbonOpacity = baseLineOpacity * (1.0 + Double(beatGlow) * 0.3)
                    let ribbonColors = blendedColors.map { $0.opacity(ribbonOpacity) }
                    let ribbonWidth = isCore ? max(1.4, 2.5 * systemFraction) : max(0.5, 0.8 * systemFraction)
                    
                    context.stroke(
                        ribbonPath,
                        with: .linearGradient(
                            Gradient(colors: ribbonColors),
                            startPoint: isLeft ? CGPoint(x: 0, y: 0) : CGPoint(x: size.width, y: 0),
                            endPoint: isLeft ? CGPoint(x: size.width * 0.5, y: 0) : CGPoint(x: size.width * 0.5, y: 0)
                        ),
                        lineWidth: ribbonWidth
                    )
                    
                    // High-energy central vacuum pressure line (neon glowing core)
                    if isCore {
                        let coreGlowOpacity = 0.58 * (1.0 + Double(beatGlow) * 0.45)
                        context.stroke(
                            ribbonPath,
                            with: .color(Color.white.opacity(coreGlowOpacity)),
                            lineWidth: max(0.6, 1.0 * systemFraction)
                        )
                    }
                }
            }
            
            // ==========================================
            // PASS 3: HIGH-SPEED DUAL-PARTICLE FLOWS & FLYING SPARKS
            // ==========================================
            let particlesPerFilament = 14
            for sys in 0..<numSystems {
                for fil in 0..<numFilaments {
                    let isCore = (fil == 0)
                    let systemFraction = CGFloat(fil) / 3.0
                    
                    for p in 0..<particlesPerFilament {
                        // Position u: slides smoothly downstream over time
                        let flowSpeed: CGFloat = (isCore ? 0.15 : 0.10) * CGFloat(flowSpeedMultiplier)
                        let baseU = CGFloat(p) / CGFloat(particlesPerFilament)
                        let u = fract(baseU + t * flowSpeed)
                        
                        let coords = getVortexCoords(sys, fil, u)
                        let (pt, audioVal, pScale, opacity, finalColor) = project3DPoint(coords.px, coords.py, coords.pz, u, coords.audioVal)
                        
                        guard pt.x.isFinite && pt.y.isFinite else { continue }
                        
                        // Prevent edge pops
                        let edgeFade: Double = {
                            if u < 0.08 {
                                return Double(u / 0.08)
                            } else if u > 0.86 {
                                return Double((1.0 - u) / 0.14)
                            } else {
                                return 1.0
                            }
                        }()
                        
                        let finalOpacity = opacity * edgeFade
                        guard finalOpacity > 0.01 else { continue }
                        
                        // Spark / cloud sizes
                        let baseSize = isCore ? (2.0 + systemFraction * 2.0) : (4.0 + systemFraction * 6.0)
                        let pSize = baseSize * pScale * 0.65 * (0.35 + audioVal * 0.9)
                        
                        // Add high-treble vibration
                        let microVib: CGFloat = {
                            if trebleVal > 0.28 {
                                let vibAngle = fract(CGFloat(p) * 23.4 + t * 50.0) * 6.28
                                return sin(vibAngle) * trebleVal * 4.5
                            }
                            return 0.0
                        }()
                        
                        let pxScreen = pt.x + microVib
                        let pyScreen = pt.y + microVib
                        
                        // Draw core particle
                        context.fill(
                            Path(ellipseIn: CGRect(x: pxScreen - pSize/2, y: pyScreen - pSize/2, width: pSize, height: pSize)),
                            with: .color(finalColor.opacity(finalOpacity * 0.95))
                        )
                        
                        // Dynamic tangential sparkles shedding off wingtip vortex core filaments on treble spikes
                        if trebleVal > 0.32 && audioVal > 0.38 {
                            // Calculate tangent vector by taking a tiny step downstream
                            let nextU = min(0.99, u + 0.008)
                            let nextCoords = getVortexCoords(sys, fil, nextU)
                            let (nextPt, _, _, _, _) = project3DPoint(nextCoords.px, nextCoords.py, nextCoords.pz, nextU, nextCoords.audioVal)
                            
                            if nextPt.x.isFinite && nextPt.y.isFinite {
                                let tx = nextPt.x - pt.x
                                let ty = nextPt.y - pt.y
                                
                                // Glow spark offset
                                let offsetVal = 1.0 + sin(CGFloat(p) * 19.3 + t * 9.0) * 1.5
                                let sparkX = pxScreen + tx * offsetVal * (6.0 + trebleVal * 12.0)
                                let sparkY = pyScreen + ty * offsetVal * (6.0 + trebleVal * 12.0)
                                let sparkSize = max(0.6, pSize * 0.35)
                                
                                context.fill(
                                    Path(ellipseIn: CGRect(x: sparkX - sparkSize/2, y: sparkY - sparkSize/2, width: sparkSize, height: sparkSize)),
                                    with: .color(Color.white.opacity(finalOpacity * 0.92))
                                )
                            }
                        }
                        
                        // Render soft atmospheric aura glow around the particle
                        if audioVal > 0.20 || isCore {
                            let haloSize = pSize * (isCore ? 2.3 : 3.2)
                            let haloOpacity = finalOpacity * (isCore ? 0.30 : 0.16)
                            context.fill(
                                Path(ellipseIn: CGRect(x: pxScreen - haloSize/2, y: pyScreen - haloSize/2, width: haloSize, height: haloSize)),
                                    with: .color(finalColor.opacity(haloOpacity))
                            )
                        }
                    }
                }
            }
        }
    }
}
