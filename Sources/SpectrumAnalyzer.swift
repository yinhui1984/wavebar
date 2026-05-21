import Foundation
import Combine

/// Processes raw FFT magnitudes into visual-friendly logarithmic frequency buckets.
/// Implements auto-gain (autosens), EQ boosting, and attack/release temporal smoothing.
public final class SpectrumAnalyzer: ObservableObject {
    private let fftSize: Int
    
    // MARK: - Parameters (Main-Thread Accessible)
    @Published public var sensitivity: Float = 1.0
    @Published public var smoothness: Float = 0.12 // Release factor
    @Published public var lowBoostEnabled: Bool = true
    @Published public var fMin: Float = 50.0 {
        didSet {
            let clamped = max(20.0, min(fMin, fMax / 2.0))
            if clamped != fMin {
                fMin = clamped
            } else if fMin != oldValue {
                regenerateBucketConfigs()
            }
        }
    }
    @Published public var fMax: Float = 8000.0 {
        didSet {
            let clamped = max(fMin * 2.0, min(fMax, 22000.0))
            if clamped != fMax {
                fMax = clamped
            } else if fMax != oldValue {
                regenerateBucketConfigs()
            }
        }
    }
    @Published public var bucketCount: Int = 48 {
        didSet {
            if bucketCount != oldValue {
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
    private var attackCoeff: Float = 0.92 // Instant responsive attack
    
    private var peakVelocities: [Float] = []
    private var peakHoldFrames: [Int] = []
    
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
    }
    
    /// Smooth frequency boost curve to make low frequencies more responsive and warm.
    private func getEQGain(frequency: Float) -> Float {
        guard lowBoostEnabled else { return 1.0 }
        
        if frequency <= 200.0 {
            // High boost for deep bass: 1.8x
            return 1.8
        } else if frequency <= 500.0 {
            // Linear ramp-down from 1.8 to 1.3 for upper bass/warmth
            let t = (frequency - 200.0) / 300.0
            return 1.8 - t * 0.5
        } else if frequency <= 2000.0 {
            // Linear ramp-down from 1.3 to 0.95 for mid-range
            let t = (frequency - 500.0) / 1500.0
            return 1.3 - t * 0.35
        } else if frequency <= 8000.0 {
            // Linear ramp-down from 0.95 to 0.70 for high treble (tame hiss)
            let t = (frequency - 2000.0) / 6000.0
            return 0.95 - t * 0.25
        } else {
            return 0.70
        }
    }
    
    /// Processes a new frame of raw FFT magnitudes and updates SwiftUI output.
    /// Runs on the main thread (60 FPS UI loop).
    public func processFrame(magnitudes: [Float]) {
        guard magnitudes.count > 0, bucketConfigs.count == bucketCount else { return }
        
        var rawBucketValues = [Float](repeating: 0.0, count: bucketCount)
        var frameMax: Float = 0.0
        
        // 1. Map raw FFT bins to logarithmic buckets and apply EQ curve
        for k in 0..<bucketCount {
            let config = bucketConfigs[k]
            
            var sum: Float = 0.0
            let start = config.startBin
            let end = min(config.endBin, magnitudes.count - 1)
            
            for bin in start...end {
                sum += magnitudes[bin]
            }
            
            let avgVal = sum / Float(end - start + 1)
            let gainedVal = avgVal * getEQGain(frequency: config.centerFrequency)
            
            rawBucketValues[k] = gainedVal
            if gainedVal > frameMax {
                frameMax = gainedVal
            }
        }
        
        // 2. Adaptive Auto-Gain (Autosens)
        // Decay the running maximum slowly to track music dynamics
        runningMax = runningMax * 0.994 + frameMax * 0.006
        runningMax = max(runningMax, 0.03) // Floor to prevent noise boosting during silence
        
        // 3. Normalization, Compression, and Dynamic Attack/Release Smoothing
        let currentRelease = smoothness
        
        for k in 0..<bucketCount {
            // Normalize bucket by runningMax and apply user-controlled sensitivity
            var targetHeight = (rawBucketValues[k] * sensitivity) / runningMax
            
            // Apply power-law compression (x^0.62) to match human logarithmic decibel hearing.
            // This pulls up low-to-mid detail dynamically while keeping beats snappy.
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
                hold = 8 // Hold peak suspended for ~130ms (8 frames) before falling
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
        
        // 4. Low-Frequency Transient (Beat) Detection (50Hz - 180Hz)
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
            
            // Detect transient (sudden spike above the moving average)
            let ratio = bassAverage > 0 ? (bassEnergy / bassAverage) : 1.0
            if ratio > 1.35 && bassEnergy > 0.005 {
                // Beat trigger! Drive background pulse to max
                pulseGlow = 1.0
            }
        }
        
        // Decay the glow pulse exponentially over time
        pulseGlow = pulseGlow * 0.86
    }
}
