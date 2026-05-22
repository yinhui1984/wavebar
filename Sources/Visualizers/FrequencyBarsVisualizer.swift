import SwiftUI

public struct FrequencyBarsVisualizer: View {
    let heights: [Float]
    let blendedColors: [Color]
    let pulseGlow: Float
    
    public init(heights: [Float], blendedColors: [Color], pulseGlow: Float) {
        self.heights = heights
        self.blendedColors = blendedColors
        self.pulseGlow = pulseGlow
    }
    
    public var body: some View {
        Canvas { context, size in
            let count = heights.count
            guard count > 0 else { return }
            
            let isSmall = size.width < 320
            let spacing: CGFloat = isSmall ? 1.5 : 2.5
            let minBarWidthAndSpacing: CGFloat = isSmall ? 3.5 : 5.0
            let maxBars = max(12, Int(size.width / minBarWidthAndSpacing))
            let finalCount = min(count, maxBars)
            let totalSpacing = spacing * CGFloat(finalCount - 1)
            let barWidth = max(1.0, (size.width - totalSpacing) / CGFloat(finalCount))
            
            // Beat-driven overall canvas resonant vertical scaling
            let pulseScale = 1.0 + CGFloat(pulseGlow) * 0.08
            let topPadding: CGFloat = 0
            let bottomPadding: CGFloat = 2
            let maxBarHeight = max(10.0, size.height - topPadding - bottomPadding)
            let gradientTopY = topPadding
            
            // Batch all bars into a single path
            var combinedPath = Path()
            for i in 0..<finalCount {
                let originalIndex: Int
                if finalCount == count {
                    originalIndex = i
                } else {
                    originalIndex = Int(round(Double(i) * Double(count - 1) / Double(finalCount - 1)))
                }
                let valFraction = CGFloat(heights[max(0, min(originalIndex, count - 1))])
                let barHeight = max(1.5, valFraction * maxBarHeight * pulseScale)
                let x = CGFloat(i) * (barWidth + spacing)
                let y = size.height - barHeight - bottomPadding
                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                let cornerRadius = min(barWidth / 2, 3)
                combinedPath.addRoundedRect(in: rect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
            }
            
            let barGradient = Gradient(colors: blendedColors)
            context.fill(
                combinedPath,
                with: .linearGradient(
                    barGradient,
                    startPoint: CGPoint(x: size.width / 2, y: size.height - 6),
                    endPoint: CGPoint(x: size.width / 2, y: gradientTopY)
                )
            )
        }
    }
}
