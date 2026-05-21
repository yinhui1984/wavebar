import Foundation

/// A thread-safe, high-performance ring buffer to safely bridge the real-time audio
/// capture thread and the main UI rendering thread.
public final class AudioRingBuffer {
    private var buffer: [Float]
    private let capacity: Int
    private var writeIndex: Int = 0
    private let lock = NSLock()
    
    public init(capacity: Int = 16384) {
        self.capacity = capacity
        self.buffer = [Float](repeating: 0.0, count: capacity)
    }
    
    /// Writes new audio samples into the ring buffer.
    /// Executed on the real-time audio thread. Extremely fast, zero allocations.
    public func write(_ samples: UnsafeBufferPointer<Float>) {
        guard let baseAddress = samples.baseAddress, samples.count > 0 else { return }
        
        lock.lock()
        defer { lock.unlock() }
        
        let count = samples.count
        if count >= capacity {
            // Input exceeds buffer size, keep only the latest segment
            let offset = count - capacity
            for i in 0..<capacity {
                buffer[i] = baseAddress[offset + i]
            }
            writeIndex = 0
        } else {
            let spaceToEnd = capacity - writeIndex
            if spaceToEnd >= count {
                // Fits in single copy without wrap-around
                for i in 0..<count {
                    buffer[writeIndex + i] = baseAddress[i]
                }
                writeIndex = (writeIndex + count) % capacity
            } else {
                // Wrap-around copy
                for i in 0..<spaceToEnd {
                    buffer[writeIndex + i] = baseAddress[i]
                }
                let remaining = count - spaceToEnd
                for i in 0..<remaining {
                    buffer[i] = baseAddress[spaceToEnd + i]
                }
                writeIndex = remaining
            }
        }
    }
    
    /// Reads the latest `count` samples from the ring buffer.
    /// Executed on the UI/analysis thread. Returns samples chronologically (oldest to newest).
    public func readLatest(count: Int, into outBuffer: inout [Float]) {
        guard count <= capacity else { return }
        if outBuffer.count != count {
            outBuffer = [Float](repeating: 0.0, count: count)
        }
        
        lock.lock()
        defer { lock.unlock() }
        
        // Start reading from (writeIndex - count + capacity) % capacity
        let startReadIndex = (writeIndex - count + capacity) % capacity
        
        let spaceToEnd = capacity - startReadIndex
        if spaceToEnd >= count {
            // Contiguous read
            for i in 0..<count {
                outBuffer[i] = buffer[startReadIndex + i]
            }
        } else {
            // Wrap-around read
            for i in 0..<spaceToEnd {
                outBuffer[i] = buffer[startReadIndex + i]
            }
            let remaining = count - spaceToEnd
            for i in 0..<remaining {
                outBuffer[spaceToEnd + i] = buffer[i]
            }
        }
    }
}
