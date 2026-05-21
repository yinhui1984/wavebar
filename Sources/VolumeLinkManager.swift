import Cocoa
import CoreAudio
import Combine

public final class VolumeLinkManager: ObservableObject {
    public static let shared = VolumeLinkManager()
    
    @Published public var isEnabled: Bool = false {
        didSet {
            if isEnabled {
                startLink()
            } else {
                stopLink()
            }
        }
    }
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // Virtual device names that must remain locked at 1.0 (100%) volume
    private let virtualDeviceKeywords = ["BlackHole", "Soundflower", "Loopback", "Virtual", "Dummy", "eqMac"]
    private let volumeStep: Float = 0.0625 // 1/16th volume step
    
    private init() {
        // Load initial state
        let saved = UserDefaults.standard.bool(forKey: "wavebar.volumeLinkEnabled")
        if saved {
            // Only auto-enable if the user already granted permission
            if checkAccessibility(prompt: false) {
                self.isEnabled = true
            }
        }
    }
    
    // Check if the application has accessibility permissions
    public func checkAccessibility(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    // Instantly open System Settings direct to the Accessibility pane
    public func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
    
    public func startLink() {
        guard eventTap == nil else { return }
        guard checkAccessibility(prompt: false) else {
            self.isEnabled = false
            return
        }
        
        let eventMask = (1 << 14) // 14 is raw value for NX_SYSDEFINED
        
        // Zero-capturing Swift closure (doesn't capture any local scope variables, thus compiles cleanly to a C-function pointer)
        let callback: CGEventTapCallBack = { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
            if type.rawValue == 14 { // Literal 14 avoids capturing sysDefinedRawValue
                if let result = VolumeLinkManager.shared.handleEvent(event) {
                    return result
                }
            }
            return Unmanaged.passRetained(event)
        }
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: nil
        ) else {
            print("VolumeLinkManager: Failed to create event tap")
            self.isEnabled = false
            return
        }
        
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        self.eventTap = tap
        self.runLoopSource = source
        UserDefaults.standard.set(true, forKey: "wavebar.volumeLinkEnabled")
        print("VolumeLinkManager: Successfully activated global event tap")
    }
    
    public func stopLink() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        UserDefaults.standard.set(false, forKey: "wavebar.volumeLinkEnabled")
        print("VolumeLinkManager: Deactivated global event tap")
    }
    
    // Core event tap handler
    fileprivate func handleEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let nsEvent = NSEvent(cgEvent: event) else { return Unmanaged.passRetained(event) }
        
        // Subtype 8 identifies media hotkeys
        if nsEvent.type == .systemDefined && nsEvent.subtype.rawValue == 8 {
            let data = nsEvent.data1
            let keyCode = Int32((data & 0xFFFF0000) >> 16)
            let keyFlags = (data & 0x0000FFFF)
            let keyState = (((keyFlags & 0xFF00) >> 8))
            let isKeyDown = (keyState == 0x0A)
            
            if isKeyDown {
                switch keyCode {
                case 0: // NX_KEYTYPE_SOUND_UP
                    adjustVolume(direction: 1.0)
                    return nil // Intercept & swallow event to block OS mute/ban icons
                case 1: // NX_KEYTYPE_SOUND_DOWN
                    adjustVolume(direction: -1.0)
                    return nil
                case 2: // NX_KEYTYPE_SOUND_MUT
                    toggleMute()
                    return nil
                default:
                    break
                }
            }
        }
        return Unmanaged.passRetained(event)
    }
    
    // CoreAudio Helper: Default Output Device
    private func getDefaultOutputDevice() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceID
    }
    
    // CoreAudio Helper: Sub-devices for Aggregate Devices
    private func getSubDevices(of deviceID: AudioDeviceID) -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyActiveSubDeviceList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        if status != noErr || size == 0 {
            return [deviceID]
        }
        
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var subDevices = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &subDevices)
        return subDevices
    }
    
    // CoreAudio Helper: Device Name
    private func getDeviceName(_ deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        if status == noErr, let unmanagedName = name {
            return unmanagedName.takeRetainedValue() as String
        }
        return "Unknown"
    }
    
    // CoreAudio Helper: Get volume scalar
    private func getVolume(of deviceID: AudioDeviceID) -> Float {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var volume: Float = 0.0
        var size = UInt32(MemoryLayout<Float>.size)
        var status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        if status != noErr {
            // Fallback to channel 1 if master channel volume is missing
            address.mElement = 1
            status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        }
        return (status == noErr) ? volume : 1.0
    }
    
    // CoreAudio Helper: Set volume scalar
    private func setVolume(of deviceID: AudioDeviceID, to volume: Float) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var isWritable: DarwinBoolean = false
        let status = AudioObjectIsPropertySettable(deviceID, &address, &isWritable)
        
        var targetVol = volume
        let size = UInt32(MemoryLayout<Float>.size)
        
        if status == noErr && isWritable.boolValue {
            AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &targetVol)
        } else {
            // Apply volume changes sequentially to stereo channels if main channel is not writable
            for ch in 1...2 {
                address.mElement = UInt32(ch)
                AudioObjectIsPropertySettable(deviceID, &address, &isWritable)
                if isWritable.boolValue {
                    AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &targetVol)
                }
            }
        }
    }
    
    // CoreAudio Helper: Mute
    private func getMute(of deviceID: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var mute: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &mute)
        if status != noErr {
            address.mElement = 1
            status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &mute)
        }
        return (status == noErr) ? mute : 0
    }
    
    private func setMute(of deviceID: AudioDeviceID, to mute: UInt32) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var isWritable: DarwinBoolean = false
        let status = AudioObjectIsPropertySettable(deviceID, &address, &isWritable)
        var val = mute
        let size = UInt32(MemoryLayout<UInt32>.size)
        if status == noErr && isWritable.boolValue {
            AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &val)
        } else {
            for ch in 1...2 {
                address.mElement = UInt32(ch)
                AudioObjectIsPropertySettable(deviceID, &address, &isWritable)
                if isWritable.boolValue {
                    AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &val)
                }
            }
        }
    }
    
    // Adjust volume logic
    private func adjustVolume(direction: Float) {
        let defaultOut = getDefaultOutputDevice()
        let subDevices = getSubDevices(of: defaultOut)
        
        for device in subDevices {
            let name = getDeviceName(device)
            let isVirtual = virtualDeviceKeywords.contains { name.localizedCaseInsensitiveContains($0) }
            
            if isVirtual {
                // Safeguard: Lock loopback/virtual audio devices strictly to 1.0 (100%) volume to preserve spectrum input amplitude
                setVolume(of: device, to: 1.0)
                setMute(of: device, to: 0)
            } else {
                // Scale physical audio devices (e.g. Speakers, Headphones)
                let currentVol = getVolume(of: device)
                let targetVol = max(0.0, min(1.0, currentVol + direction * volumeStep))
                setVolume(of: device, to: targetVol)
            }
        }
    }
    
    // Toggle mute logic
    private func toggleMute() {
        let defaultOut = getDefaultOutputDevice()
        let subDevices = getSubDevices(of: defaultOut)
        
        var isMuted: UInt32 = 0
        var hasQueriedMute = false
        
        for device in subDevices {
            let name = getDeviceName(device)
            let isVirtual = virtualDeviceKeywords.contains { name.localizedCaseInsensitiveContains($0) }
            
            if isVirtual {
                setMute(of: device, to: 0)
            } else {
                if !hasQueriedMute {
                    isMuted = getMute(of: device)
                    hasQueriedMute = true
                }
                let targetMute: UInt32 = (isMuted == 1) ? 0 : 1
                setMute(of: device, to: targetMute)
            }
        }
    }
}
