//
//  FadeCurveShape.swift
//  mixbridge
//
//  Visual representation of fade curve types for the curve picker.
//

import SwiftUI

struct FadeCurveShape: Shape {
    let curve: FadeCurve
    let showFadeIn: Bool
    let showFadeOut: Bool
    
    init(curve: FadeCurve, showFadeIn: Bool = true, showFadeOut: Bool = true) {
        self.curve = curve
        self.showFadeIn = showFadeIn
        self.showFadeOut = showFadeOut
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 50
        
        if showFadeOut {
            // Draw fade-out curve (top-left to bottom-right)
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            
            for i in 0...steps {
                let progress = Double(i) / Double(steps)
                let gain = Double(curve.fadeOutGain(progress: progress))
                let x = rect.minX + rect.width * progress
                let y = rect.minY + rect.height * (1 - gain)
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        if showFadeIn && showFadeOut {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else if showFadeIn {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        
        if showFadeIn {
            // Draw fade-in curve (bottom-left to top-right)
            for i in 0...steps {
                let progress = Double(i) / Double(steps)
                let gain = Double(curve.fadeInGain(progress: progress))
                let x = rect.minX + rect.width * progress
                let y = rect.minY + rect.height * (1 - gain)
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        return path
    }
}

struct FadeCurvePreview: View {
    let curve: FadeCurve
    
    var body: some View {
        VStack(spacing: 12) {
            // Curve visualization
            ZStack {
                // Grid lines
                VStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { i in
                        if i > 0 {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.15))
                                .frame(height: 1)
                        }
                        if i < 4 {
                            Spacer()
                        }
                    }
                }
                
                // Fade-out curve (outgoing track - solid)
                FadeCurveShape(curve: curve, showFadeIn: false, showFadeOut: true)
                    .stroke(
                        Color.blue,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
                
                // Fade-in curve (incoming track - dashed)
                FadeCurveShape(curve: curve, showFadeIn: true, showFadeOut: false)
                    .stroke(
                        Color.blue.opacity(0.5),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [6, 6])
                    )
            }
            .frame(height: 120)
            .padding(.horizontal, 8)
            
            // Legend
            HStack(spacing: 24) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue)
                        .frame(width: 20, height: 3)
                    Text("Fade Out")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue.opacity(0.5))
                        .frame(width: 20, height: 3)
                    Text("Fade In")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Axis labels
            HStack {
                Text("0%")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("Time")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("100%")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ForEach(FadeCurve.allCases, id: \.self) { curve in
            VStack(alignment: .leading, spacing: 8) {
                Text(curve.displayName)
                    .font(.headline)
                FadeCurvePreview(curve: curve)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    .padding()
}
