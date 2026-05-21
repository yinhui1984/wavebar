import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox

/// Representation of an active physical or virtual audio input device.
public struct AudioDevice: Identifiable, Hashable {
    public var id: AudioObjectID
    public var name: String
    
    public init(id: AudioObjectID, name: String) {
        self.id = id
        self.name = name
    }
}

/// Manages CoreAudio device enumerations and drives the AVAudioEngine recording tap.
public final class AudioEngineManager: ObservableObject {
    @Published public var devices: [AudioDevice] = []
    @Published public var selectedDeviceID: AudioObjectID? = nil
    @Published public var isRunning: Bool = false
    @Published public var sampleRate: Double = 44100.0
    @Published public var errorMessage: String? = nil
    
    private let audioEngine = AVAudioEngine()
    private let ringBuffer: AudioRingBuffer
    
    // Pre-allocated downmix buffer to prevent dynamic heap allocations in the realtime audio callback
    private var downmixBuffer = [Float](repeating: 0.0, count: 16384)
    
    public init(ringBuffer: AudioRingBuffer) {
        self.ringBuffer = ringBuffer
        
        refreshDevices()
        autoSelectDevice()
    }
    
    /// Enumerates all active input devices from macOS CoreAudio using AudioObject API.
    public func refreshDevices() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        guard status == noErr else {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to query CoreAudio devices count (Status \(status))"
            }
            return
        }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        
        guard status == noErr else {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to query CoreAudio devices IDs (Status \(status))"
            }
            return
        }
        
        var list: [AudioDevice] = []
        
        for id in deviceIDs {
            // 1. Query device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var name: Unmanaged<CFString>? = nil
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            status = AudioObjectGetPropertyData(
                id,
                &nameAddress,
                0,
                nil,
                &nameSize,
                &name
            )
            
            let deviceName = (status == noErr && name != nil) ? (name!.takeRetainedValue() as String) : "Unknown Device"
            
            // 2. Query channel layout to determine if it acts as an input device
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var inputSize: UInt32 = 0
            status = AudioObjectGetPropertyDataSize(
                id,
                &inputAddress,
                0,
                nil,
                &inputSize
            )
            
            var isInput = false
            if status == noErr && inputSize > 0 {
                let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(inputSize))
                defer { bufferList.deallocate() }
                
                status = AudioObjectGetPropertyData(
                    id,
                    &inputAddress,
                    0,
                    nil,
                    &inputSize,
                    bufferList
                )
                
                if status == noErr {
                    let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
                    let channels = buffers.reduce(0) { $0 + $1.mNumberChannels }
                    if channels > 0 {
                        isInput = true
                    }
                }
            }
            
            if isInput {
                list.append(AudioDevice(id: id, name: deviceName))
            }
        }
        
        DispatchQueue.main.async {
            self.devices = list
        }
    }
    
    /// Scans the available devices list and picks BlackHole as primary target, falling back gracefully.
    public func autoSelectDevice() {
        if let blackHole2ch = devices.first(where: { $0.name.localizedCaseInsensitiveContains("BlackHole 2ch") }) {
            selectedDeviceID = blackHole2ch.id
        } else if let blackHoleAny = devices.first(where: { $0.name.localizedCaseInsensitiveContains("BlackHole") }) {
            selectedDeviceID = blackHoleAny.id
        } else if let fallback = devices.first {
            selectedDeviceID = fallback.id
        }
        
        if let initialID = selectedDeviceID {
            start(deviceID: initialID)
        } else {
            DispatchQueue.main.async {
                self.errorMessage = "No active audio input devices found. Please configure BlackHole or connect a microphone."
            }
        }
    }
    
    /// Starts the AVAudioEngine stream utilizing the selected device ID.
    public func start(deviceID: AudioObjectID) {
        stop()
        
        DispatchQueue.main.async {
            self.selectedDeviceID = deviceID
        }
        
        let inputNode = audioEngine.inputNode
        guard let audioUnit = inputNode.audioUnit else {
            DispatchQueue.main.async {
                self.errorMessage = "AVAudioEngine input node has no underlying AudioUnit."
            }
            return
        }
        
        // 1. Assign selected device ID to AudioUnit properties (HAL output)
        var devID = deviceID
        var status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &devID,
            UInt32(MemoryLayout<AudioObjectID>.size)
        )
        
        guard status == noErr else {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to target input device \(deviceID) (Error: \(status))"
            }
            return
        }
        
        // 2. Fetch nominal sample rate of chosen device
        var srAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sr: Double = 44100.0
        var srSize = UInt32(MemoryLayout<Double>.size)
        status = AudioObjectGetPropertyData(
            deviceID,
            &srAddress,
            0,
            nil,
            &srSize,
            &sr
        )
        
        DispatchQueue.main.async {
            if status == noErr {
                self.sampleRate = sr
            }
        }
        
        // 3. Configure tap on AVAudioEngine inputNode bus 0
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            guard let floatData = buffer.floatChannelData else { return }
            
            let channels = Int(buffer.format.channelCount)
            let frameLength = Int(buffer.frameLength)
            
            if channels == 1 {
                // Direct mono write
                let monoBuffer = UnsafeBufferPointer(start: floatData[0], count: frameLength)
                self.ringBuffer.write(monoBuffer)
            } else if channels >= 2 {
                // Downmix stereo/multichannel to mono using pre-allocated instance array
                let limit = min(frameLength, self.downmixBuffer.count)
                
                for f in 0..<limit {
                    var sum: Float = 0.0
                    for c in 0..<channels {
                        sum += floatData[c][f]
                    }
                    self.downmixBuffer[f] = sum / Float(channels)
                }
                
                self.downmixBuffer.withUnsafeBufferPointer { ptr in
                    let slice = UnsafeBufferPointer(start: ptr.baseAddress!, count: limit)
                    self.ringBuffer.write(slice)
                }
            }
        }
        
        // 4. Prepare and start AVAudioEngine
        do {
            audioEngine.prepare()
            try audioEngine.start()
            DispatchQueue.main.async {
                self.isRunning = true
                self.errorMessage = nil
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to start AVAudioEngine: \(error.localizedDescription)"
            }
        }
    }
    
    /// Stops the AVAudioEngine stream and cleans up installed taps.
    public func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        DispatchQueue.main.async {
            self.isRunning = false
        }
    }
}
