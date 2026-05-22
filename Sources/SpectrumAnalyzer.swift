import Foundation
import Combine

/// Processes raw FFT magnitudes into visual-friendly logarithmic frequency buckets.
/// Implements auto-gain (autosens), EQ boosting, and attack/release temporal smoothing.
public final class SpectrumAnalyzer: ObservableObject {
    private let fftSize: Int
    
    // MARK: - Parameters (Main-Thread Accessible)
    @Published public var sensitivity: Float = {
        let saved = UserDefaults.standard.float(forKey: "wavebar.sensitivity")
        return saved > 0.0 ? saved : 1.0
    }() {
        didSet {
            UserDefaults.standard.set(sensitivity, forKey: "wavebar.sensitivity")
        }
    }
    
    @Published public var smoothness: Float = {
        let saved = UserDefaults.standard.float(forKey: "wavebar.smoothness")
        return saved > 0.0 ? saved : 0.12 // Release factor
    }() {
        didSet {
            UserDefaults.standard.set(smoothness, forKey: "wavebar.smoothness")
        }
    }
    
    @Published public var lowBoostEnabled: Bool = {
        return UserDefaults.standard.object(forKey: "wavebar.lowBoostEnabled") as? Bool ?? true
    }() {
        didSet {
            UserDefaults.standard.set(lowBoostEnabled, forKey: "wavebar.lowBoostEnabled")
        }
    }
    
    @Published public var fMin: Float = {
        let saved = UserDefaults.standard.float(forKey: "wavebar.fMin")
        return saved > 0.0 ? saved : 50.0
    }() {
        didSet {
            let clamped = max(20.0, min(fMin, fMax / 2.0))
            if clamped != fMin {
                fMin = clamped
            } else {
                UserDefaults.standard.set(fMin, forKey: "wavebar.fMin")
                if fMin != oldValue {
                    regenerateBucketConfigs()
                }
            }
        }
    }
    
    @Published public var fMax: Float = {
        let saved = UserDefaults.standard.float(forKey: "wavebar.fMax")
        return saved > 0.0 ? saved : 8000.0
    }() {
        didSet {
            let clamped = max(fMin * 2.0, min(fMax, 22000.0))
            if clamped != fMax {
                fMax = clamped
            } else {
                UserDefaults.standard.set(fMax, forKey: "wavebar.fMax")
                if fMax != oldValue {
                    regenerateBucketConfigs()
                }
            }
        }
    }
    
    @Published public var bucketCount: Int = {
        let saved = UserDefaults.standard.integer(forKey: "wavebar.bucketCount")
        return saved > 0 ? saved : 48
    }() {
        didSet {
            if bucketCount != oldValue {
                UserDefaults.standard.set(bucketCount, forKey: "wavebar.bucketCount")
                regenerateBucketConfigs()
            }
        }
    }
    
    // MARK: - Output States for SwiftUI
    @Published public var smoothedHeights: [Float] = []
    @Published public var peakHeights: [Float] = []
    @Published public var pulseGlow: Float = 0.0
    
    // MARK: - Internal DSP & Physics States
    private var sampleRate: Double = 44100.0
    private var runningMax: Float = 0.1
    private var bassAverage: Float = 0.05
    private var attackCoeff: Float = 1.0 // Instant responsive attack
    
    private var peakVelocities: [Float] = []
    private var peakHoldFrames: [Int] = []
    private var runningMaxes: [Float] = []
    
    private struct BucketConfig {
        let startBin: Int
        let endBin: Int
        let centerFrequency: Float
    }
    private var bucketConfigs: [BucketConfig] = []
    
    public init(fftSize: Int = 2048) {
        self.fftSize = fftSize
        self.smoothedHeights = [Float](repeating: 0.0, count: bucketCount)
        self.peakHeights = [Float](repeating: 0.0, count: bucketCount)
        self.peakVelocities = [Float](repeating: 0.0, count: bucketCount)
        self.peakHoldFrames = [Int](repeating: 0, count: bucketCount)
        self.runningMaxes = [Float](repeating: 0.1, count: bucketCount)
        regenerateBucketConfigs()
    }
    
    /// Updates the sample rate and rebuilds logarithmic buckets if necessary.
    public func updateSampleRate(_ newSampleRate: Double) {
        guard newSampleRate > 0 else { return }
        if abs(self.sampleRate - newSampleRate) > 1.0 {
            self.sampleRate = newSampleRate
            regenerateBucketConfigs()
        }
    }
    
    /// Re-calculates boundaries for the logarithmic spacing between 50Hz and 8000Hz.
    private func regenerateBucketConfigs() {
        bucketConfigs.removeAll()
        
        let fMin: Float = self.fMin
        let fMax: Float = self.fMax
        let n = Float(fftSize)
        let fs = Float(sampleRate)
        
        for k in 0..<bucketCount {
            // Logarithmic spacing formula
            let fStart = fMin * pow(fMax / fMin, Float(k) / Float(bucketCount))
            let fEnd = fMin * pow(fMax / fMin, Float(k + 1) / Float(bucketCount))
            
            // Map frequencies to FFT bin indices
            let binStart = fStart * n / fs
            let binEnd = fEnd * n / fs
            
            // Ensure indices are within safe boundaries and non-empty
            let start = max(1, Int(floor(binStart)))
            let end = max(start, Int(ceil(binEnd)))
            
            let centerFreq = (fStart + fEnd) / 2.0
            
            bucketConfigs.append(BucketConfig(startBin: start, endBin: end, centerFrequency: centerFreq))
        }
        
        // Resize dynamic physics buffers to match bucket count
        if smoothedHeights.count != bucketCount {
            smoothedHeights = [Float](repeating: 0.0, count: bucketCount)
        }
        if peakHeights.count != bucketCount {
            peakHeights = [Float](repeating: 0.0, count: bucketCount)
            peakVelocities = [Float](repeating: 0.0, count: bucketCount)
            peakHoldFrames = [Int](repeating: 0, count: bucketCount)
        }
        if runningMaxes.count != bucketCount {
            runningMaxes = [Float](repeating: 0.1, count: bucketCount)
        }
    }
    
    /// Smooth frequency boost curve to make low frequencies more responsive and warm.
    private func getEQGain(frequency: Float) -> Float {
        // Base low EQ boost
        var gain: Float = 1.0
        if lowBoostEnabled {
            if frequency <= 200.0 {
                // High boost for deep bass: 1.8x
                gain = 1.8
            } else if frequency <= 500.0 {
                // Linear ramp-down from 1.8 to 1.2 for upper bass/warmth
                let t = (frequency - 200.0) / 300.0
                gain = 1.8 - t * 0.6
            } else if frequency <= 2000.0 {
                // Linear ramp-down from 1.2 to 1.0 for mid-range
                let t = (frequency - 500.0) / 1500.0
                gain = 1.2 - t * 0.2
            }
        }
        
        // Spectral tilt compensation (compensates for natural 1/f energy falloff in music)
        // High frequencies naturally have 10x-30x less amplitude than low frequencies.
        // We apply a gentle slope starting from 200Hz to balance the spectrum visually.
        if frequency > 200.0 {
            let tilt = pow(frequency / 200.0, 0.65)
            gain *= tilt
        }
        
        return gain
    }
    
    /// Processes a new frame of raw FFT magnitudes and updates SwiftUI output.
    /// Runs on the main thread (60 FPS UI loop).
    public func processFrame(magnitudes: [Float]) {
        guard magnitudes.count > 0, bucketConfigs.count == bucketCount else { return }
        
        var rawBucketValues = [Float](repeating: 0.0, count: bucketCount)
        var frameMax: Float = 0.0
        
        // 1. Map raw FFT bins to logarithmic buckets (using Hybrid HF Mapping for high-freq accuracy)
        for k in 0..<bucketCount {
            let config = bucketConfigs[k]
            
            var sum: Float = 0.0
            var maxVal: Float = 0.0
            let start = config.startBin
            let end = min(config.endBin, magnitudes.count - 1)
            
            for bin in start...end {
                let val = magnitudes[bin]
                sum += val
                if val > maxVal {
                    maxVal = val
                }
            }
            
            let avgVal = sum / Float(end - start + 1)
            
            // High-frequency detail boost: above 2kHz, mix max and average to make transients pop out
            let frequency = config.centerFrequency
            let hybridVal: Float
            if frequency > 2000.0 {
                let t = min(1.0, (frequency - 2000.0) / 6000.0)
                let maxWeight = t * 0.85 // Up to 85% peak/max bin, 15% average above 8kHz
                hybridVal = maxVal * maxWeight + avgVal * (1.0 - maxWeight)
            } else {
                hybridVal = avgVal
            }
            
            let gainedVal = hybridVal * getEQGain(frequency: frequency)
            rawBucketValues[k] = gainedVal
            if gainedVal > frameMax {
                frameMax = gainedVal
            }
        }
        
        // 2. Low-Frequency Transient (Beat) Detection (50Hz - 180Hz)
        var bassSum: Float = 0.0
        var bassCount = 0
        
        for k in 0..<bucketCount {
            let freq = bucketConfigs[k].centerFrequency
            if freq >= 50.0 && freq <= 180.0 {
                bassSum += rawBucketValues[k]
                bassCount += 1
            }
        }
        
        if bassCount > 0 {
            let bassEnergy = bassSum / Float(bassCount)
            
            // Slow-moving average of the bass band
            bassAverage = bassAverage * 0.97 + bassEnergy * 0.03
            
            // Detect transient ratio (current energy vs moving average)
            let ratio = bassAverage > 0 ? (bassEnergy / bassAverage) : 1.0
            
            // Proportional Glow: continuous, non-linear scaling with dynamic energy gate
            let energyFactor = min(1.0, bassEnergy / 0.02)
            let excessRatio = max(0.0, ratio - 1.0)
            let targetGlow = pow(excessRatio, 2.0) * 1.6 * energyFactor
            
            // Allow instant attack but cap at a premium intense glow maximum (1.8)
            pulseGlow = max(pulseGlow, min(1.8, targetGlow))
        }
        
        // 3. Adaptive Auto-Gain (Autosens) with Noise Gate
        // Decay the running maximum slowly to track music dynamics
        runningMax = runningMax * 0.994 + frameMax * 0.006
        
        // If the frame is extremely silent, increase the noise floor floor to prevent noise dancing
        let noiseFloor: Float = (frameMax < 0.0005) ? 0.25 : 0.03
        runningMax = max(runningMax, noiseFloor)
        
        // 4. Normalization, Compression, and Dynamic Attack/Release Smoothing + Peak Physics
        let currentRelease = smoothness
        
        for k in 0..<bucketCount {
            // Decoupled / Multi-band dynamic range mapping:
            // Update the local running maximum for this specific bucket
            let val = rawBucketValues[k]
            runningMaxes[k] = runningMaxes[k] * 0.992 + val * 0.008
            
            // local noise gate floor to prevent silent channel dancing
            let localMax = max(runningMaxes[k], 0.01)
            
            // Blend global and local running max (45% global shape, 55% local dynamic recovery)
            let blendedMax = runningMax * 0.45 + localMax * 0.55
            
            // Normalize bucket and apply user-controlled sensitivity
            var targetHeight = (val * sensitivity) / blendedMax
            
            // Apply power-law compression (x^0.62) to match human logarithmic decibel hearing
            targetHeight = pow(targetHeight, 0.62)
            targetHeight = min(max(targetHeight, 0.0), 1.0)
            
            // Temporal smoothing: instant responsive attack, fluid release
            let prevHeight = smoothedHeights[k]
            let coeff = (targetHeight > prevHeight) ? attackCoeff : currentRelease
            let smoothed = prevHeight + coeff * (targetHeight - prevHeight)
            smoothedHeights[k] = smoothed
            
            // --- Peak Indicator Physics (Constant Gravity Acceleration) ---
            var peak = peakHeights[k]
            var vel = peakVelocities[k]
            var hold = peakHoldFrames[k]
            
            if smoothed >= peak {
                peak = smoothed
                vel = 0.0
                // Hang peaks longer on stronger beats (15 frames) vs normal frames (8 frames)
                let isStrongBeat = pulseGlow > 0.6
                hold = isStrongBeat ? 15 : 8
            } else {
                if hold > 0 {
                    hold -= 1
                } else {
                    let gravity: Float = 0.006 // Smooth constant gravity pull
                    vel += gravity
                    peak -= vel
                    if peak < smoothed {
                        peak = smoothed
                        vel = 0.0
                    }
                }
            }
            
            peakHeights[k] = max(0.0, min(peak, 1.0))
            peakVelocities[k] = vel
            peakHoldFrames[k] = hold
        }
        
        // Decay the glow pulse exponentially over time
        pulseGlow = pulseGlow * 0.86
    }
}
