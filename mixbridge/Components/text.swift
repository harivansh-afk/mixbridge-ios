//
//  text.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/21/25.
//

import SwiftUI

/// Glass-Effect Text View
/// Fallsback to given color for older versions
struct GlassEffectText: View {
    var text: String
    var font: UIFont
    var fallbackColor: Color = .primary
    var body: some View {
        let textShape = TextToShape(value: text, font: font)
        Text(text)
            .font(Font(font))
            .opacity(0)
            .glassEffect(.clear, in: textShape)
    }
}

/// Text-To-Shape
struct TextToShape: Shape {
    var value: String
    var font: UIFont
    func path(in rect: CGRect) -> Path {
        var path = Path()
        font.drawGlyphs(value) { position, glyphPath in
            let transform = CGAffineTransform(translationX: position.x, y: position.y)
                .scaledBy(x: 1, y: -1)
            let newPath = Path(glyphPath).applying(transform)
            /// Adding it to the main Path
            path.addPath(newPath)
        }

        /// Centering to the current bounds
        let bounds = path.boundingRect
        let offsetX = rect.midX - bounds.midX
        let offsetY = rect.midY - bounds.midY
        let centerTransform = CGAffineTransform(translationX: offsetX, y: offsetY)

        return path.applying(centerTransform)
    }
}

extension UIFont {
    /// Converting UIFont into CTFont
    nonisolated
    var ctFont: CTFont {
        let descriptor = self.fontDescriptor
        return CTFontCreateWithFontDescriptor(descriptor, 0, nil)
    }
    nonisolated
    /// Converting Font into a NSAttributedString with the given value
    func toNSAttributedString(_ value: String) -> NSAttributedString {
        return NSAttributedString(string: value, attributes: [.font: self])
    }
    nonisolated
    /// Calculating TextSize for the given font
    func toSize(_ value: String) -> CGSize {
        return NSString(string: value).size(withAttributes: [.font: self])
    }

    /// Return's Each Individual Glyph Path from the given text using the current font (Can be used to Draw Text as Path)
    func drawGlyphs(_ value: String, draw: @escaping (_ position: CGPoint, _ glyphPath: CGPath) -> ()) {
        let ctFont = self.ctFont
        let attributedString = self.toNSAttributedString(value)
        /// Extracting Lines & Runs from the Attributed String using CoreText APIs
        let lines = CTLineCreateWithAttributedString(attributedString)
        let runs = CTLineGetGlyphRuns(lines)

        for runIndex in 0..<CFArrayGetCount(runs) {
            let run = unsafeBitCast(CFArrayGetValueAtIndex(runs, runIndex), to: CTRun.self)
            let runCount = CTRunGetGlyphCount(run)

            /// Iterating Run and drawing Each Glyph
            for index in 0..<runCount {
                let range = CFRangeMake(index, 1)
                var glyph = CGGlyph()
                var position = CGPoint()

                /// Extracting Values
                CTRunGetGlyphs(run, range, &glyph)
                CTRunGetPositions(run, range, &position)

                if let glyphPath = CTFontCreatePathForGlyph(ctFont, glyph, nil) {
                    /// Passing to draw!
                    draw(position, glyphPath)
                }
            }
        }
    }
}



#Preview {
    ZStack {
        Rectangle()
            .foregroundStyle(.clear)
            .overlay (
                Image("background")
            )
        GlassEffectText(
            text: "mixbridge",
            font: .init(name: "InstrumentSerif-Italic", size: 100) ?? .systemFont(ofSize: 100)
        )
    }
}
