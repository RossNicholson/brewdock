import SwiftUI

/// BrewDock's mascot: a waving coffee mug in the rubber-hose cartoon style of
/// the Don't Worry and Word Slip characters (thick ink outlines, pastel fills,
/// big eyes, white glove). Drawn on a pastel disc so it reads in dark mode too.
struct Mascot: View {
    enum Mood { case happy, sleepy }

    var mood: Mood = .happy
    var size: CGFloat = 72
    var disc: Color = AppColors.butter

    private static let ink = Color(hex: 0x232428)
    private static let mug = Color(hex: 0xC3C7F6)       // periwinkle
    private static let mugShade = Color(hex: 0xA9AEEB)
    private static let coffee = Color(hex: 0x7A5240)
    private static let crema = Color(hex: 0xA97A5C)
    private static let sclera = Color(hex: 0xFBF6E9)
    private static let blush = Color(hex: 0xF6C3B4)     // peach

    var body: some View {
        Canvas { context, canvasSize in
            // Draw in a 100×100 space
            let scale = min(canvasSize.width, canvasSize.height) / 100
            context.scaleBy(x: scale, y: scale)
            draw(in: &context)
        }
        .frame(width: size, height: size)
        .background(disc, in: Circle())
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext) {
        let ink = Self.ink
        let outline = StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)

        // Steam
        for x in [41.0, 50.0, 59.0] {
            var steam = Path()
            steam.move(to: CGPoint(x: x, y: 27))
            steam.addCurve(to: CGPoint(x: x, y: 12),
                           control1: CGPoint(x: x - 5, y: 22),
                           control2: CGPoint(x: x + 5, y: 17))
            context.stroke(steam, with: .color(ink.opacity(0.45)),
                           style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        }

        // Handle: a thick ink ring with a mug-coloured ring inside it
        let handle = Path(ellipseIn: CGRect(x: 63, y: 45, width: 19, height: 24))
        context.stroke(handle, with: .color(ink), lineWidth: 9)
        context.stroke(handle, with: .color(Self.mug), lineWidth: 3.8)

        // Body, slightly tapered
        var body = Path()
        body.move(to: CGPoint(x: 27, y: 35))
        body.addLine(to: CGPoint(x: 71, y: 35))
        body.addLine(to: CGPoint(x: 68, y: 80))
        body.addQuadCurve(to: CGPoint(x: 61, y: 87), control: CGPoint(x: 67.5, y: 87))
        body.addLine(to: CGPoint(x: 37, y: 87))
        body.addQuadCurve(to: CGPoint(x: 30, y: 80), control: CGPoint(x: 30.5, y: 87))
        body.closeSubpath()
        context.fill(body, with: .color(Self.mug))
        // Shade down the right side
        context.drawLayer { layer in
            layer.clip(to: body)
            layer.fill(Path(CGRect(x: 60, y: 30, width: 20, height: 60)), with: .color(Self.mugShade))
        }
        context.stroke(body, with: .color(ink), style: outline)

        // Rim with coffee
        let rim = Path(ellipseIn: CGRect(x: 26, y: 30, width: 46, height: 11))
        context.fill(rim, with: .color(Self.coffee))
        context.fill(Path(ellipseIn: CGRect(x: 33, y: 32.5, width: 18, height: 4)), with: .color(Self.crema))
        context.stroke(rim, with: .color(ink), style: outline)

        // Cheeks
        for x in [32.0, 58.0] {
            context.fill(Path(ellipseIn: CGRect(x: x, y: 69, width: 8, height: 4.5)),
                         with: .color(Self.blush))
        }

        // Eyes
        for x in [36.0, 51.0] {
            let eyeRect = CGRect(x: x, y: 50, width: 12, height: 15)
            switch mood {
            case .happy:
                let eye = Path(ellipseIn: eyeRect)
                context.fill(eye, with: .color(Self.sclera))
                context.stroke(eye, with: .color(ink), lineWidth: 2.2)
                context.fill(Path(ellipseIn: CGRect(x: x + 4, y: 54.5, width: 7, height: 9)), with: .color(ink))
                context.fill(Path(ellipseIn: CGRect(x: x + 5.3, y: 55.6, width: 2.6, height: 2.6)), with: .color(.white))
            case .sleepy:
                var lid = Path()
                lid.move(to: CGPoint(x: x + 1, y: 58))
                lid.addQuadCurve(to: CGPoint(x: x + 11, y: 58), control: CGPoint(x: x + 6, y: 63))
                context.stroke(lid, with: .color(ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            }
            // Brow
            var brow = Path()
            brow.move(to: CGPoint(x: x + 2, y: 47))
            brow.addQuadCurve(to: CGPoint(x: x + 10, y: 47), control: CGPoint(x: x + 6, y: 43.5))
            context.stroke(brow, with: .color(ink), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        }

        // Smile
        var smile = Path()
        smile.move(to: CGPoint(x: 43.5, y: 74))
        smile.addQuadCurve(to: CGPoint(x: 53.5, y: 74), control: CGPoint(x: 48.5, y: 79.5))
        context.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

        // Waving rubber-hose arm with a white glove
        var arm = Path()
        arm.move(to: CGPoint(x: 30, y: 63))
        arm.addCurve(to: CGPoint(x: 16, y: 46),
                     control1: CGPoint(x: 20, y: 66),
                     control2: CGPoint(x: 14, y: 56))
        context.stroke(arm, with: .color(ink), style: StrokeStyle(lineWidth: 3.6, lineCap: .round))
        let glove = Path(ellipseIn: CGRect(x: 9.5, y: 35, width: 13, height: 12.5))
        context.fill(glove, with: .color(.white))
        context.stroke(glove, with: .color(ink), lineWidth: 2.2)
        let thumb = Path(ellipseIn: CGRect(x: 19, y: 39, width: 6, height: 5.5))
        context.fill(thumb, with: .color(.white))
        context.stroke(thumb, with: .color(ink), lineWidth: 2)
        // Glove finger creases
        for dx in [13.5, 16.5] {
            var crease = Path()
            crease.move(to: CGPoint(x: dx, y: 37.5))
            crease.addLine(to: CGPoint(x: dx, y: 41))
            context.stroke(crease, with: .color(ink), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
    }
}
