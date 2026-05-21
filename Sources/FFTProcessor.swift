import Accelerate
import Foundation

/// Performs real-to-complex FFT spectral analysis on audio buffers.
/// Highly optimized with pre-allocated working buffers and reusable FFT setup.
public final class FFTProcessor {
    public let fftSize: Int
    private let log2n: vDSP_Length
    
    // Opaque vDSP FFT setup object
    private let fftSetup: FFTSetup
    
    // Hann window to smooth boundaries and prevent spectral leakage
    private var window: [Float]
    
    // Pre-allocated temporary buffers to avoid dynamic allocation during analysis
    private var complexReals: [Float]
    private var complexImaginaries: [Float]
    
    public init?(fftSize: Int = 2048) {
        // Ensure fftSize is a power of 2
        guard fftSize > 0 && (fftSize & (fftSize - 1)) == 0 else {
            return nil
        }
        
        self.fftSize = fftSize
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return nil
        }
        self.fftSetup = setup
        
        // Generate Hann window
        self.window = [Float](repeating: 0.0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        
        let halfSize = fftSize / 2
        self.complexReals = [Float](repeating: 0.0, count: halfSize)
        self.complexImaginaries = [Float](repeating: 0.0, count: halfSize)
    }
    
    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }
    
    /// Analyzes raw PCM floats and computes their amplitude spectrum.
    /// - Parameters:
    ///   - samples: Input real PCM buffer (must have size == `fftSize`).
    ///   - magnitudes: Destination buffer to receive halfSize magnitude results.
    public func analyze(samples: [Float], magnitudes: inout [Float]) {
        let halfSize = fftSize / 2
        guard samples.count == fftSize else { return }
        
        if magnitudes.count != halfSize {
            magnitudes = [Float](repeating: 0.0, count: halfSize)
        }
        
        // 1. Apply Hann window: windowed = samples * window
        var windowed = [Float](repeating: 0.0, count: fftSize)
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))
        
        // 2. Convert interleaved real data to split-complex format
        windowed.withUnsafeBufferPointer { windowedPtr in
            complexReals.withUnsafeMutableBufferPointer { realPtr in
                complexImaginaries.withUnsafeMutableBufferPointer { imagPtr in
                    var splitComplex = DSPSplitComplex(
                        realp: realPtr.baseAddress!,
                        imagp: imagPtr.baseAddress!
                    )
                    
                    // Rebound UnsafePointer<Float> to UnsafePointer<DSPComplex>
                    windowedPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { complexPtr in
                        // Pack real samples (stride 2) into split-complex representation
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfSize))
                    }
                    
                    // 3. Perform Forward Real FFT (In-place on splitComplex)
                    vDSP_fft_zrip(
                        fftSetup,
                        &splitComplex,
                        1,
                        log2n,
                        FFTDirection(kFFTDirection_Forward)
                    )
                }
            }
        }
        
        // 4. Calculate squared magnitudes: magnitudes = real^2 + imag^2
        complexReals.withUnsafeBufferPointer { realPtr in
            complexImaginaries.withUnsafeBufferPointer { imagPtr in
                var split = DSPSplitComplex(
                    realp: UnsafeMutablePointer(mutating: realPtr.baseAddress!),
                    imagp: UnsafeMutablePointer(mutating: imagPtr.baseAddress!)
                )
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfSize))
            }
        }
        
        // 5. Take square root to get absolute amplitudes: magnitudes = sqrt(magnitudes)
        var count = Int32(halfSize)
        vvsqrtf(&magnitudes, magnitudes, &count)
        
        // 6. Scale amplitudes: since vDSP FFT scales by a factor of 2, 
        // divide by fftSize to normalize.
        var scale = 1.0 / Float(fftSize)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(halfSize))
    }
}
