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
        
        // Listen for window key/focus events to dynamically show/hide window control buttons
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidBecomeKey(_:)), name: NSWindow.didBecomeKeyNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidResignKey(_:)), name: NSWindow.didResignKeyNotification, object: nil)
        
        // Set up initial windows after they have had a chance to render
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApp.windows {
                self.configureWindow(window)
            }
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    @objc func windowDidBecomeKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            configureWindow(window, isKey: true)
        }
    }
    
    @objc func windowDidResignKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            configureWindow(window, isKey: false)
        }
    }
    
    private var hasConfiguredInitialFrame = false
    
    private func configureWindow(_ window: NSWindow, isKey: Bool? = nil) {
        // Run on main thread to prevent threading issues with AppKit
        DispatchQueue.main.async {
            // Keep window floating on top for premium picture-in-picture convenience
            window.level = .floating
            
            // Set initial centered window frame of 750x200 exactly once on startup
            if !self.hasConfiguredInitialFrame {
                self.hasConfiguredInitialFrame = true
                
                // Disable window autosave / frame restoration to force our default size
                window.setFrameAutosaveName("")
                
                let targetSize = NSSize(width: 750, height: 200)
                let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect.zero
                
                if screenFrame != NSRect.zero {
                    let originX = screenFrame.origin.x + (screenFrame.width - targetSize.width) / 2
                    let originY = screenFrame.origin.y + (screenFrame.height - targetSize.height) / 2
                    let targetFrame = NSRect(origin: NSPoint(x: originX, y: originY), size: targetSize)
                    window.setFrame(targetFrame, display: true, animate: false)
                } else {
                    window.setContentSize(targetSize)
                }
            }
            
            let keyState = isKey ?? window.isKeyWindow
            // Hide standard close/minimize/maximize buttons when window is not active/focused
            window.standardWindowButton(.closeButton)?.isHidden = !keyState
            window.standardWindowButton(.miniaturizeButton)?.isHidden = !keyState
            window.standardWindowButton(.zoomButton)?.isHidden = !keyState
        }
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
        let processor = FFTProcessor(fftSize: 1024)!
        let analyzer = SpectrumAnalyzer(fftSize: 1024)
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
