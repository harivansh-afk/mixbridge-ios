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
    
    @State private var segments: [TextSegment]
    
    init(text: String, font: UIFont) {
        self.text = text
        self.font = font
        _segments = State(initialValue: text.splitByEmoji())
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
        .task(id: text) {
            let updated = text.splitByEmoji()
            await MainActor.run {
                segments = updated
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
    var leftFade: CGFloat = 7
    var rightFade: CGFloat = 7
    var startDelay: Double = 5.0
    var spacing: CGFloat = 56
    var loopsBeforePause: Int = 3
    var isPlaying: Bool = true

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var phase: Phase = .stopped(offset: 0)
    @State private var loopCounter: Int = 0
    @State private var startTask: Task<Void, Never>?

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
    
    private enum Phase: Equatable {
        case stopped(offset: CGFloat)
        case waiting(offset: CGFloat, until: Date)
        case scrolling(referenceDate: Date, referenceOffset: CGFloat, stopAtLoopEnd: Bool)
        
        var isScrolling: Bool {
            if case .scrolling = self { return true }
            return false
        }
        
        var frozenOffset: CGFloat {
            switch self {
            case .stopped(let offset): return offset
            case .waiting(let offset, _): return offset
            case .scrolling: return 0
            }
        }
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
                    TimelineView(.animation(minimumInterval: 1.0 / 120.0, paused: !phase.isScrolling)) { context in
                        let tick = tickState(for: context.date)
                        marqueeContent(offset: tick.offset)
                            .onChange(of: tick.loopsSinceReference) { oldValue, newValue in
                                guard newValue > oldValue else { return }
                                handleLoopAdvance(delta: newValue - oldValue, at: context.date)
                            }
                    }
                } else if textWidth > 0 {
                    // Only show centered text if it actually fits
                    GlassEffectText(text: text, font: font)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: max(geo.size.width, 1), height: max(geo.size.height, 1), alignment: .leading)
            .onChange(of: geo.size.width) { _, newWidth in
                if newWidth.isFinite && newWidth > 0 {
                    containerWidth = newWidth
                    syncState(now: Date())
                }
            }
        }
        .frame(height: safeHeight)
        .clipped()
        .mask(fadeMask)
        .onChange(of: text) { _, _ in resetForNewTrack() }
        .onChange(of: isPlaying) { _, _ in syncState(now: Date()) }
        .onAppear {
            syncState(now: Date())
        }
        .onDisappear {
            startTask?.cancel()
            startTask = nil
        }
    }

    @ViewBuilder
    private func marqueeContent(offset: CGFloat) -> some View {
        HStack(spacing: spacing) {
            LeftAlignedGlassText(text: text, font: font)
            LeftAlignedGlassText(text: text, font: font)
        }
        .fixedSize(horizontal: true, vertical: false)
        .offset(x: offset)
    }
    
    private struct TickState {
        let offset: CGFloat
        let loopsSinceReference: Int
    }
    
    private func tickState(for date: Date) -> TickState {
        guard needsScroll else { return .init(offset: 0, loopsSinceReference: 0) }
        
        switch phase {
        case .stopped(let offset):
            return .init(offset: normalizedOffset(offset), loopsSinceReference: 0)
        case .waiting(let offset, _):
            return .init(offset: normalizedOffset(offset), loopsSinceReference: 0)
        case .scrolling(let referenceDate, let referenceOffset, _):
            let baseSpeed: CGFloat = 50.0
            let delta = max(date.timeIntervalSince(referenceDate), 0)
            let distance = baseSpeed * CGFloat(delta)
            let width = segmentWidth
            
            if width <= 0 || !width.isFinite {
                return .init(offset: 0, loopsSinceReference: 0)
            }
            
            let startPosition = positiveModulo(-referenceOffset, width)
            let total = startPosition + distance
            let loops = Int(total / width)
            let position = positiveModulo(total, width)
            let offset = (-position).isFinite ? -position : 0
            return .init(offset: normalizedOffset(offset), loopsSinceReference: loops)
        }
    }

    private func measurementReader(geo: GeometryProxy) -> some View {
        GeometryReader { textGeo in
            Color.clear
                .onAppear {
                    if textGeo.size.width.isFinite && textGeo.size.width > 0 {
                        textWidth = textGeo.size.width
                    }
                    if geo.size.width.isFinite && geo.size.width > 0 {
                        containerWidth = geo.size.width
                    }
                    syncState(now: Date())
                }
                .onChange(of: textGeo.size.width) { _, newWidth in
                    if newWidth.isFinite && newWidth > 0 {
                        textWidth = newWidth
                        syncState(now: Date())
                    }
                }
        }
    }

    // Only show fade when text is actually moving (not during delay or when paused)
    private var showFade: Bool {
        needsScroll && phase.isScrolling
    }

    private var fadeMask: some View {
        Group {
            if showFade {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: leftFade)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: rightFade)
                }
            } else {
                Color.black
            }
        }
    }
    
    private func syncState(now: Date) {
        guard needsScroll else {
            cancelStartTask()
            phase = .stopped(offset: 0)
            loopCounter = 0
            return
        }
        
        if !isPlaying {
            cancelStartTask()
            loopCounter = 0
            switch phase {
            case .scrolling(let referenceDate, let referenceOffset, _):
                phase = .scrolling(referenceDate: referenceDate, referenceOffset: referenceOffset, stopAtLoopEnd: true)
            case .waiting, .stopped:
                phase = .stopped(offset: 0)
            }
            return
        }
        
        switch phase {
        case .scrolling(let referenceDate, let referenceOffset, let stopAtLoopEnd):
            if stopAtLoopEnd {
                // Playback resumed before the stop point - keep going smoothly.
                phase = .scrolling(referenceDate: referenceDate, referenceOffset: referenceOffset, stopAtLoopEnd: false)
            }
            return
        case .waiting:
            return
        case .stopped(let offset):
            scheduleStart(from: offset, delay: startDelay)
        }
    }
    
    private func resetForNewTrack() {
        cancelStartTask()
        phase = .stopped(offset: 0)
        loopCounter = 0
        syncState(now: Date())
    }
    
    private func handleLoopAdvance(delta: Int, at date: Date) {
        guard delta > 0 else { return }
        
        if case .scrolling(_, _, let stopAtLoopEnd) = phase, stopAtLoopEnd {
            // Old behavior: when paused, finish the current loop and then stop at the boundary.
            cancelStartTask()
            phase = .stopped(offset: 0)
            loopCounter = 0
            return
        }
        
        guard loopsBeforePause > 0 else { return }
        guard isPlaying, needsScroll else { return }
        guard phase.isScrolling else { return }
        
        loopCounter += delta
        guard loopCounter > 0, loopCounter % loopsBeforePause == 0 else { return }
        
        let offset = tickState(for: date).offset
        scheduleStart(from: offset, delay: startDelay)
    }
    
    private func scheduleStart(from offset: CGFloat, delay: Double) {
        cancelStartTask()
        loopCounter = 0
        
        let frozen = normalizedOffset(offset)
        let delaySeconds = delay.isFinite ? max(delay, 0) : 0
        guard delaySeconds > 0 else {
            phase = .scrolling(referenceDate: Date(), referenceOffset: frozen, stopAtLoopEnd: false)
            return
        }
        
        phase = .waiting(offset: frozen, until: Date().addingTimeInterval(delaySeconds))
        
        let nanoseconds = UInt64(min(delaySeconds, 3600.0) * 1_000_000_000)
        startTask = Task {
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            
            if Task.isCancelled { return }
            
            await MainActor.run {
                guard needsScroll, isPlaying else { return }
                guard case .waiting(let waitingOffset, _) = phase else { return }
                phase = .scrolling(referenceDate: Date(), referenceOffset: normalizedOffset(waitingOffset), stopAtLoopEnd: false)
            }
        }
    }
    
    private func cancelStartTask() {
        startTask?.cancel()
        startTask = nil
    }
    
    private func positiveModulo(_ value: CGFloat, _ modulus: CGFloat) -> CGFloat {
        guard modulus.isFinite, modulus > 0 else { return 0 }
        let result = value.truncatingRemainder(dividingBy: modulus)
        return result < 0 ? result + modulus : result
    }
    
    private func normalizedOffset(_ offset: CGFloat) -> CGFloat {
        let width = segmentWidth
        guard width.isFinite, width > 0 else { return 0 }
        let normalized = -positiveModulo(-offset, width)
        return normalized.isFinite ? normalized : 0
    }

}

// MARK: - Left-Aligned Glass Text

/// Glass effect text left-aligned (for marquee)
/// Renders emojis as normal text since they don't have glyph paths
struct LeftAlignedGlassText: View {
    let text: String
    let font: UIFont
    
    @State private var segments: [TextSegment]
    
    init(text: String, font: UIFont) {
        self.text = text
        self.font = font
        _segments = State(initialValue: text.splitByEmoji())
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
        .task(id: text) {
            let updated = text.splitByEmoji()
            await MainActor.run {
                segments = updated
            }
        }
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
    /// Only excludes actual emojis from liquid glass - punctuation and symbols render fine
    func splitByEmoji() -> [TextSegment] {
        var segments: [TextSegment] = []
        var currentText = ""
        var currentIsEmoji = false

        for character in self {
            // Use Swift's built-in emoji detection on the full character (handles multi-scalar emojis)
            let isEmoji = character.unicodeScalars.first.map { scalar in
                // Only treat as emoji if it has emoji presentation (actual pictographic emoji)
                // This excludes punctuation, symbols, and other characters that render fine in glass
                scalar.properties.isEmojiPresentation
                    || (scalar.properties.isEmoji && character.unicodeScalars.contains { $0.value == 0xFE0F })
            } ?? false

            if currentText.isEmpty {
                currentIsEmoji = isEmoji
                currentText.append(character)
            } else if isEmoji == currentIsEmoji {
                currentText.append(character)
            } else {
                // Switch type - save current and start new
                if !currentText.isEmpty {
                    segments.append(TextSegment(text: currentText, isEmoji: currentIsEmoji))
                }
                currentText = String(character)
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
