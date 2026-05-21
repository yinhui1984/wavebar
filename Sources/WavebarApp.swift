import SwiftUI
import AppKit

/// App delegate to safely handle macOS-specific application lifecycle events.
/// This guarantees that AppKit has fully initialized before we interact with NSApp.
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Elevate standalone SPM compiled command-line binary to standard regular GUI App.
        // This registers it in the macOS Dock, brings it to the front, and handles key bindings.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Programmatic SwiftUI App wrapper for a standalone executable on macOS.
public struct WavebarApp: App {
    // Attach our custom AppDelegate to manage initialization safely
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @StateObject private var audioEngineManager: AudioEngineManager
    @StateObject private var spectrumAnalyzer: SpectrumAnalyzer
    
    private let ringBuffer: AudioRingBuffer
    private let fftProcessor: FFTProcessor
    
    public init() {
        let ring = AudioRingBuffer(capacity: 16384)
        let processor = FFTProcessor(fftSize: 2048)!
        let analyzer = SpectrumAnalyzer(fftSize: 2048)
        let manager = AudioEngineManager(ringBuffer: ring)
        
        self.ringBuffer = ring
        self.fftProcessor = processor
        _spectrumAnalyzer = StateObject(wrappedValue: analyzer)
        _audioEngineManager = StateObject(wrappedValue: manager)
    }
    
    public var body: some Scene {
        WindowGroup("Wavebar") {
            MainView(
                audioEngineManager: audioEngineManager,
                spectrumAnalyzer: spectrumAnalyzer,
                ringBuffer: ringBuffer,
                fftProcessor: fftProcessor
            )
        }
        .windowStyle(.hiddenTitleBar)
    }
}
