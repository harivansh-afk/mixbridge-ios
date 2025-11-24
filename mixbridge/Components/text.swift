//
//  text.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/21/25.
//

import SwiftUI

// MARK: - Glass Effect Text

/// Static glass-effect text view (centered)
struct GlassEffectText: View {
    let text: String
    let font: UIFont

    var body: some View {
        Text(text)
            .font(Font(font))
            .opacity(0)
            .glassEffect(.clear, in: TextToShape(value: text, font: font))
    }
}

// MARK: - Marquee Glass Text

/// Infinite scrolling liquid glass text (Apple Music style)
struct MarqueeGlassText: View {
    let text: String
    let font: UIFont
    var leftFade: CGFloat = 10
    var rightFade: CGFloat = 10
    var startDelay: Double = 5.0
    var spacing: CGFloat = 56

    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var isAnimating = false
    @State private var loopCount = 0

    private var needsScroll: Bool {
        textWidth > 0 && containerWidth > 0 && textWidth > containerWidth + 1
    }

    private var segmentWidth: CGFloat {
        max(textWidth + spacing, 1)
    }

    private var scrollDuration: Double {
        let duration = Double(segmentWidth) / 45
        return duration.isFinite && duration > 0 ? duration : 1.0
    }

    private var safeHeight: CGFloat {
        let height = font.lineHeight + 6
        return height.isFinite && height > 0 ? height : 40
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Hidden text for measurement
                Text(text)
                    .font(Font(font))
                    .fixedSize()
                    .background(measurementReader(geo: geo))
                    .opacity(0)

                // Visible content
                if needsScroll {
                    HStack(spacing: spacing) {
                        LeftAlignedGlassText(text: text, font: font)
                        LeftAlignedGlassText(text: text, font: font)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: offset.isFinite ? offset : 0)
                } else if textWidth > 0 {
                    GlassEffectText(text: text, font: font)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: max(geo.size.width, 1), height: max(geo.size.height, 1), alignment: .leading)
            .onChange(of: geo.size.width) { _, newWidth in
                if newWidth.isFinite && newWidth > 0 { containerWidth = newWidth }
            }
        }
        .frame(height: safeHeight)
        .clipped()
        .mask(fadeMask)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { startAnimationIfNeeded() }
        }
        .onDisappear { isAnimating = false }
        .onChange(of: text) { _, _ in resetAnimation() }
    }

    private func measurementReader(geo: GeometryProxy) -> some View {
        GeometryReader { textGeo in
            Color.clear
                .onAppear {
                    if textGeo.size.width.isFinite && textGeo.size.width > 0 { textWidth = textGeo.size.width }
                    if geo.size.width.isFinite && geo.size.width > 0 { containerWidth = geo.size.width }
                }
                .onChange(of: textGeo.size.width) { _, newWidth in
                    if newWidth.isFinite && newWidth > 0 { textWidth = newWidth }
                }
        }
    }

    private var fadeMask: some View {
        HStack(spacing: 0) {
            if needsScroll {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: leftFade)
            }
            Color.black
            if needsScroll {
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: rightFade)
            }
        }
    }

    private func startAnimationIfNeeded() {
        guard needsScroll, !isAnimating else { return }
        isAnimating = true
        loopCount = 0
        setOffset(0)

        DispatchQueue.main.asyncAfter(deadline: .now() + startDelay) {
            guard isAnimating else { return }
            runContinuousScroll()
        }
    }

    private func runContinuousScroll() {
        guard isAnimating, needsScroll, segmentWidth > 0 else {
            isAnimating = false
            return
        }

        let targetOffset = -segmentWidth
        guard targetOffset.isFinite else { return }

        withAnimation(.linear(duration: scrollDuration)) {
            offset = targetOffset
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + scrollDuration) {
            guard isAnimating else { return }
            loopCount += 1
            setOffset(5)

            let delay = loopCount >= 3 ? startDelay : 0.016
            if loopCount >= 3 { loopCount = 0 }

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard isAnimating else { return }
                runContinuousScroll()
            }
        }
    }

    private func resetAnimation() {
        isAnimating = false
        setOffset(5)
        textWidth = 0
        loopCount = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { startAnimationIfNeeded() }
    }

    private func setOffset(_ value: CGFloat) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { offset = value }
    }
}

// MARK: - Left-Aligned Glass Text

/// Glass effect text left-aligned (for marquee)
struct LeftAlignedGlassText: View {
    let text: String
    let font: UIFont

    var body: some View {
        Text(text)
            .font(Font(font))
            .fixedSize()
            .opacity(0)
            .glassEffect(.clear, in: LeftAlignedTextShape(value: text, font: font))
    }
}

// MARK: - Text Shapes

/// Centered text shape for glass effect
struct TextToShape: Shape {
    var value: String
    var font: UIFont

    func path(in rect: CGRect) -> Path {
        var path = Path()
        font.drawGlyphs(value) { position, glyphPath in
            let transform = CGAffineTransform(translationX: position.x, y: position.y).scaledBy(x: 1, y: -1)
            path.addPath(Path(glyphPath).applying(transform))
        }
        let bounds = path.boundingRect
        return path.applying(CGAffineTransform(translationX: rect.midX - bounds.midX, y: rect.midY - bounds.midY))
    }
}

/// Left-aligned text shape for marquee
struct LeftAlignedTextShape: Shape {
    var value: String
    var font: UIFont

    func path(in rect: CGRect) -> Path {
        var path = Path()
        font.drawGlyphs(value) { position, glyphPath in
            let transform = CGAffineTransform(translationX: position.x, y: position.y).scaledBy(x: 1, y: -1)
            path.addPath(Path(glyphPath).applying(transform))
        }
        let bounds = path.boundingRect
        return path.applying(CGAffineTransform(translationX: -bounds.minX, y: rect.midY - bounds.midY))
    }
}

// MARK: - UIFont Extensions

extension UIFont {
    nonisolated var ctFont: CTFont {
        CTFontCreateWithFontDescriptor(fontDescriptor, 0, nil)
    }

    nonisolated func toNSAttributedString(_ value: String) -> NSAttributedString {
        NSAttributedString(string: value, attributes: [.font: self])
    }

    nonisolated func toSize(_ value: String) -> CGSize {
        NSString(string: value).size(withAttributes: [.font: self])
    }

    func drawGlyphs(_ value: String, draw: @escaping (_ position: CGPoint, _ glyphPath: CGPath) -> Void) {
        let line = CTLineCreateWithAttributedString(toNSAttributedString(value))
        let runs = CTLineGetGlyphRuns(line)

        for runIndex in 0..<CFArrayGetCount(runs) {
            let run = unsafeBitCast(CFArrayGetValueAtIndex(runs, runIndex), to: CTRun.self)
            for index in 0..<CTRunGetGlyphCount(run) {
                let range = CFRangeMake(index, 1)
                var glyph = CGGlyph()
                var position = CGPoint()
                CTRunGetGlyphs(run, range, &glyph)
                CTRunGetPositions(run, range, &position)
                if let glyphPath = CTFontCreatePathForGlyph(ctFont, glyph, nil) {
                    draw(position, glyphPath)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Rectangle()
            .foregroundStyle(.clear)
            .overlay(Image("background"))
        GlassEffectText(
            text: "mixbridge",
            font: .init(name: "InstrumentSerif-Italic", size: 100) ?? .systemFont(ofSize: 100)
        )
    }
}
