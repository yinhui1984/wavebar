import SwiftUI

/// Defines color palettes and custom behavioral/physical characteristics for different visualizer styles.
public enum VisualizerTheme: String, CaseIterable, Identifiable {
    case aurora = "Aurora"      // Deep Indigo -> Teal -> Cyan -> Mint White
    case midnight = "Midnight"  // Indigo -> Violet -> Magenta -> Pink
    case copper = "Sunset"      // Burgundy -> Crimson -> Amber -> Gold
    case monochrome = "Silver"  // Graphite -> Slate -> Silver -> White
    
    public var id: String { self.rawValue }
    
    // MARK: - Color Aesthetics
    public var colors: [Color] {
        switch self {
        case .aurora:
            return [
                Color(red: 0.05, green: 0.35, blue: 0.55).opacity(0.85),
                Color(red: 0.0, green: 0.75, blue: 0.70),
                Color(red: 0.0, green: 0.9, blue: 0.85),
                Color(red: 0.8, green: 1.0, blue: 0.9)
            ]
        case .midnight:
            return [
                Color(red: 0.15, green: 0.05, blue: 0.45).opacity(0.85),
                Color(red: 0.35, green: 0.1, blue: 0.75),
                Color(red: 0.65, green: 0.2, blue: 0.85),
                Color(red: 0.95, green: 0.6, blue: 0.85)
            ]
        case .copper:
            return [
                Color(red: 0.35, green: 0.05, blue: 0.15).opacity(0.85),
                Color(red: 0.7, green: 0.15, blue: 0.15),
                Color(red: 0.95, green: 0.45, blue: 0.15),
                Color(red: 1.0, green: 0.85, blue: 0.5)
            ]
        case .monochrome:
            return [
                Color(red: 0.15, green: 0.18, blue: 0.22).opacity(0.85),
                Color(red: 0.35, green: 0.38, blue: 0.42),
                Color(red: 0.65, green: 0.68, blue: 0.72),
                Color(red: 0.95, green: 0.97, blue: 1.0)
            ]
        }
    }
    
    public var glowColor: Color {
        switch self {
        case .aurora:
            return Color.teal
        case .midnight:
            return Color.purple
        case .copper:
            return Color.orange
        case .monochrome:
            return Color(red: 0.4, green: 0.5, blue: 0.6)
        }
    }
    
    // MARK: - Behavioral/Physical Profiles
    
    /// Global glow scaling factor. Makes neon themes pop, and graphite themes more subtle.
    public var glowIntensity: Double {
        switch self {
        case .aurora:
            return 1.0
        case .midnight:
            return 1.25 // Bright intense glow
        case .copper:
            return 0.85 // Warm dim glow
        case .monochrome:
            return 0.5  // Minimal reflection
        }
    }
    
    /// Physics reaction speed multiplier for attack/release response.
    public var physicsResponsiveness: Double {
        switch self {
        case .aurora:
            return 1.0  // Balanced natural response
        case .midnight:
            return 1.15 // Fast snappy reaction
        case .copper:
            return 0.8  // Slowly heavy responsive inertia
        case .monochrome:
            return 0.9  // Robotic/mechanical response
        }
    }
    
    /// Viscosity/gel density factor passed to Metal Shaders.
    /// Controls whether fluid is gaseous and highly dynamic, or dense like magma flow.
    public var gelViscosity: Double {
        switch self {
        case .aurora:
            return 0.55 // Standard highly dynamic gel
        case .midnight:
            return 0.4  // Fluid/low density plasma
        case .copper:
            return 0.85 // Thick, heavy magma lava flow
        case .monochrome:
            return 0.1  // Metallic high-tension mercury fluid
        }
    }
}
