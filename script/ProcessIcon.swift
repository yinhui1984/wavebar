import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 3 else {
    print("Usage: ProcessIcon <input_path> <output_path>")
    exit(1)
}

let inputPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]

print("Loading original icon from: \(inputPath)")
guard let image = NSImage(contentsOfFile: inputPath) else {
    print("Error: Could not load image from \(inputPath)")
    exit(1)
}

guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("Error: Could not retrieve CGImage")
    exit(1)
}

let width = cgImage.width
let height = cgImage.height
print("Processing \(width)x\(height) image...")

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: width * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    print("Error: Could not create input CGContext")
    exit(1)
}

context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

guard let buffer = context.data else {
    print("Error: Could not get buffer data")
    exit(1)
}

let totalPixels = width * height
let ptr = buffer.bindMemory(to: UInt8.self, capacity: totalPixels * 4)

// We define our reference background color from the top-left corner pixel (0,0)
let bgR = Double(ptr[0])
let bgG = Double(ptr[1])
let bgB = Double(ptr[2])
print("Detected background color: R=\(bgR) G=\(bgG) B=\(bgB)")

// Create a new context for output to store our processed transparent pixels
guard let outputContext = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: width * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    print("Error: Could not create output CGContext")
    exit(1)
}

guard let outBuffer = outputContext.data else {
    print("Error: Could not get output buffer data")
    exit(1)
}
let outPtr = outBuffer.bindMemory(to: UInt8.self, capacity: totalPixels * 4)

let centerX = Double(width) / 2.0
let centerY = Double(height) / 2.0

// Loop through and process each pixel
for y in 0..<height {
    for x in 0..<width {
        let offset = (y * width + x) * 4
        let r = Double(ptr[offset])
        let g = Double(ptr[offset + 1])
        let b = Double(ptr[offset + 2])
        let a = Double(ptr[offset + 3])
        
        let dx = Double(x) - centerX
        let dy = Double(y) - centerY
        let distance = sqrt(dx*dx + dy*dy)
        
        // Default: keep the pixel exactly as is
        var outR = r
        var outG = g
        var outB = b
        var outA = a
        
        // Only process pixels outside the safe radius
        if distance > 320.0 {
            let rRatio = r / bgR
            let gRatio = g / bgG
            let bRatio = b / bgB
            let ratio = min(rRatio, min(gRatio, bRatio))
            
            // Define thresholds for background and shadow transition
            let thresholdMin = 0.70
            let thresholdMax = 0.98
            
            if ratio >= thresholdMax {
                // Pure background - fully transparent
                outR = 0
                outG = 0
                outB = 0
                outA = 0
            } else if ratio <= thresholdMin {
                // Opaque body of the squircle - keep original opaque
                outR = r
                outG = g
                outB = b
                outA = 255
            } else {
                // Transition / Shadow region: apply smooth Hermite interpolation
                let t = (ratio - thresholdMin) / (thresholdMax - thresholdMin)
                // Hermite ease-in-ease-out curve
                let smoothT = t * t * (3.0 - 2.0 * t)
                let targetAlpha = 1.0 - smoothT
                
                // Unblend the pixel color from the background to recover the true shadow color
                let unblendedR = (r - (1.0 - targetAlpha) * bgR) / targetAlpha
                let unblendedG = (g - (1.0 - targetAlpha) * bgG) / targetAlpha
                let unblendedB = (b - (1.0 - targetAlpha) * bgB) / targetAlpha
                
                // Clip values to [0, 255] and fade the shadow to black as alpha approaches 0
                let clipR = max(0.0, min(255.0, unblendedR))
                let clipG = max(0.0, min(255.0, unblendedG))
                let clipB = max(0.0, min(255.0, unblendedB))
                
                // If the target alpha is very small, fade the color to black/dark to avoid noise
                let fadeFactor = targetAlpha < 0.10 ? (targetAlpha / 0.10) : 1.0
                
                outR = clipR * fadeFactor
                outG = clipG * fadeFactor
                outB = clipB * fadeFactor
                outA = targetAlpha * 255.0
            }
        }
        
        // Write the processed pixel back with premultiplied alpha (since we are using premultipliedLast)
        let alphaScale = outA / 255.0
        outPtr[offset] = UInt8(max(0.0, min(255.0, outR * alphaScale)))
        outPtr[offset + 1] = UInt8(max(0.0, min(255.0, outG * alphaScale)))
        outPtr[offset + 2] = UInt8(max(0.0, min(255.0, outB * alphaScale)))
        outPtr[offset + 3] = UInt8(max(0.0, min(255.0, outA)))
    }
}

// Generate CGImage from the output context
guard let outCGImage = outputContext.makeImage() else {
    print("Error: Could not retrieve output CGImage")
    exit(1)
}

// Save the processed CGImage to PNG file
let newImage = NSImage(cgImage: outCGImage, size: NSSize(width: width, height: height))
guard let tiffRepresentation = newImage.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
    print("Error: Could not create bitmap representation for output")
    exit(1)
}
guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    print("Error: Could not represent output as PNG")
    exit(1)
}

do {
    try pngData.write(to: URL(fileURLWithPath: outputPath))
    print("Successfully processed and saved transparent icon to: \(outputPath)")
} catch {
    print("Error: Failed to write output file: \(error)")
    exit(1)
}
