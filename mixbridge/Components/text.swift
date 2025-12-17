//
//  text.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/21/25.
//

import SwiftUI

// MARK: - Glass Effect Text

/// Static glass-effect text view (centered)
/// Renders emojis as normal text since they don't have glyph paths
struct GlassEffectText: View {
    let text: String
    let font: UIFont

    private var segments: [TextSegment] {
        text.splitByEmoji()
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                if segment.isEmoji {
                    Text(segment.text)
                        .font(Font(font))
                } else {
                    Text(segment.text)
                        .font(Font(font))
                        .opacity(0)
                        .glassEffect(.clear, in: TextToShape(value: segment.text, font: font))
                }
            }
        }
    }
}

// MARK: - Marquee Glass Text

/// Infinite scrolling liquid glass text (Apple Music style)
/// Optimized with TimelineView for 120fps ProMotion support and lower CPU usage
struct MarqueeGlassText: View {
    let text: String
    let font: UIFont
    var leftFade: CGFloat = 10
    var rightFade: CGFloat = 10
    var startDelay: Double = 5.0
    var spacing: CGFloat = 56
    var loopsBeforePause: Int = 3
    var isPlaying: Bool = true

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var animationStartDate: Date?
    @State private var lastLoopCount: Int = 0
    @State private var isStopped = true // Start stopped, only move when playing
    @State private var pendingStop = false // Stop at next loop end

    private var needsScroll: Bool {
        textWidth > 0 && containerWidth > 0 && textWidth > containerWidth + 1
    }

    private var segmentWidth: CGFloat {
        max(textWidth + spacing, 1)
    }

    private var scrollDuration: Double {
        let baseSpeed: CGFloat = 50.0
        let duration = Double(segmentWidth) / Double(baseSpeed)
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

                // Always use marquee layout (no view switching)
                if needsScroll {
                    TimelineView(.animation(minimumInterval: 1.0 / 120.0, paused: isStopped)) { context in
                        marqueeContent(date: context.date)
                    }
                } else if textWidth > 0 {
                    // Only show centered text if it actually fits
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
        .onChange(of: text) { _, _ in resetForNewTrack() }
        .onChange(of: isPlaying) { _, newValue in
            if newValue {
                // Song started/resumed - start scrolling after delay
                startScrolling()
            } else {
                // Song paused - stop at next loop end
                pendingStop = true
            }
        }
        .onAppear {
            if isPlaying {
                startScrolling()
            }
        }
        .onDisappear {
            isStopped = true
            animationStartDate = nil
        }
    }

    @ViewBuilder
    private func marqueeContent(date: Date) -> some View {
        HStack(spacing: spacing) {
            LeftAlignedGlassText(text: text, font: font)
            LeftAlignedGlassText(text: text, font: font)
        }
        .fixedSize(horizontal: true, vertical: false)
        .offset(x: calculateOffset(for: date))
    }

    private func calculateOffset(for date: Date) -> CGFloat {
        guard !isStopped, let startDate = animationStartDate else {
            return 0
        }

        let elapsed = date.timeIntervalSince(startDate)
        guard elapsed > 0 else { return 0 }

        let totalLoops = Int(elapsed / scrollDuration)
        let loopProgress = fmod(elapsed / scrollDuration, 1.0)
        let offset = -loopProgress * segmentWidth

        // Detect loop completion
        if totalLoops > lastLoopCount {
            DispatchQueue.main.async {
                lastLoopCount = totalLoops

                // Check if we should stop (song paused)
                if pendingStop {
                    isStopped = true
                    pendingStop = false
                    animationStartDate = nil
                    return
                }

                // Check if we should pause for delay (every N loops)
                if totalLoops % loopsBeforePause == 0 {
                    isStopped = true
                    // Resume after delay if still playing
                    DispatchQueue.main.asyncAfter(deadline: .now() + startDelay) {
                        if isPlaying && !pendingStop {
                            animationStartDate = Date()
                            isStopped = false
                        }
                    }
                }
            }
        }

        return offset.isFinite ? offset : 0
    }

    private func measurementReader(geo: GeometryProxy) -> some View {
        GeometryReader { textGeo in
            Color.clear
                .onAppear {
                    if textGeo.size.width.isFinite && textGeo.size.width > 0 { textWidth = textGeo.size.width }
                    if geo.size.width.isFinite && geo.size.width > 0 { containerWidth = geo.size.width }
                    // Start scrolling once measured (if playing) - defer to let state update
                    DispatchQueue.main.async {
                        if isPlaying && needsScroll && isStopped {
                            startScrolling()
                        }
                    }
                }
                .onChange(of: textGeo.size.width) { _, newWidth in
                    if newWidth.isFinite && newWidth > 0 {
                        textWidth = newWidth
                        // Start scrolling once measured (if playing) - defer to let state update
                        DispatchQueue.main.async {
                            if isPlaying && needsScroll && isStopped {
                                startScrolling()
                            }
                        }
                    }
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

    private func startScrolling() {
        guard needsScroll else { return }
        pendingStop = false
        lastLoopCount = 0
        // Start after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + startDelay) {
            guard isPlaying, !pendingStop else { return }
            animationStartDate = Date()
            isStopped = false
        }
    }

    private func resetForNewTrack() {
        isStopped = true
        animationStartDate = nil
        lastLoopCount = 0
        pendingStop = false
        // Start scrolling if playing
        if isPlaying {
            startScrolling()
        }
    }
}

// MARK: - Left-Aligned Glass Text

/// Glass effect text left-aligned (for marquee)
/// Renders emojis as normal text since they don't have glyph paths
struct LeftAlignedGlassText: View {
    let text: String
    let font: UIFont

    private var segments: [TextSegment] {
        text.splitByEmoji()
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                if segment.isEmoji {
                    Text(segment.text)
                        .font(Font(font))
                } else {
                    Text(segment.text)
                        .font(Font(font))
                        .opacity(0)
                        .glassEffect(.clear, in: LeftAlignedTextShape(value: segment.text, font: font))
                }
            }
        }
        .fixedSize()
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

// MARK: - Text Segment Helper

struct TextSegment {
    let text: String
    let isEmoji: Bool
}

extension String {
    /// Splits string into segments of regular text and emojis
    func splitByEmoji() -> [TextSegment] {
        var segments: [TextSegment] = []
        var currentText = ""
        var currentIsEmoji = false

        for scalar in unicodeScalars {
            let isEmoji = scalar.properties.isEmoji && scalar.properties.isEmojiPresentation
                || scalar.value >= 0x1F600 && scalar.value <= 0x1F64F // Emoticons
                || scalar.value >= 0x1F300 && scalar.value <= 0x1F5FF // Misc Symbols
                || scalar.value >= 0x1F680 && scalar.value <= 0x1F6FF // Transport
                || scalar.value >= 0x1F1E0 && scalar.value <= 0x1F1FF // Flags
                || scalar.value >= 0x2600 && scalar.value <= 0x26FF   // Misc symbols
                || scalar.value >= 0x2700 && scalar.value <= 0x27BF   // Dingbats
                || scalar.value >= 0xFE00 && scalar.value <= 0xFE0F   // Variation selectors
                || scalar.value >= 0x1F900 && scalar.value <= 0x1F9FF // Supplemental

            if currentText.isEmpty {
                currentIsEmoji = isEmoji
                currentText.unicodeScalars.append(scalar)
            } else if isEmoji == currentIsEmoji {
                currentText.unicodeScalars.append(scalar)
            } else {
                // Switch type - save current and start new
                if !currentText.isEmpty {
                    segments.append(TextSegment(text: currentText, isEmoji: currentIsEmoji))
                }
                currentText = String(scalar)
                currentIsEmoji = isEmoji
            }
        }

        // Add final segment
        if !currentText.isEmpty {
            segments.append(TextSegment(text: currentText, isEmoji: currentIsEmoji))
        }

        return segments
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Rectangle()
            .foregroundStyle(.clear)
            .overlay(Image("background"))
        GlassEffectText(
            text: "mixbridge 🎵",
            font: .init(name: "InstrumentSerif-Italic", size: 100) ?? .systemFont(ofSize: 100)
        )
    }
}
