import AppKit
import CoreGraphics
import CoreText
import Foundation

// Regenerates both printable walkthroughs with fixed page geometry. Keeping
// the source here prevents the binary PDFs from drifting into overlap again.

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("output/pdf")
let logoPath = root.appendingPathComponent("branding/logo.png").path

let pageWidth: CGFloat = 612
let pageHeight: CGFloat = 792
let margin: CGFloat = 52

let ink = NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.12, alpha: 1)
let muted = NSColor(calibratedRed: 0.42, green: 0.44, blue: 0.47, alpha: 1)
let quiet = NSColor(calibratedRed: 0.52, green: 0.54, blue: 0.57, alpha: 1)
let green = NSColor(calibratedRed: 0.18, green: 0.49, blue: 0.27, alpha: 1)
let greenSoft = NSColor(calibratedRed: 0.90, green: 0.95, blue: 0.92, alpha: 1)
let amberSoft = NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.83, alpha: 1)
let pageBackground = NSColor(calibratedRed: 0.965, green: 0.968, blue: 0.975, alpha: 1)
let card = NSColor.white.withAlphaComponent(0.92)
let line = NSColor(calibratedWhite: 0.84, alpha: 1)

func font(_ size: CGFloat, weight: NSFont.Weight = .regular, mono: Bool = false) -> NSFont {
    if mono { return NSFont.monospacedSystemFont(ofSize: size, weight: weight) }
    return NSFont.systemFont(ofSize: size, weight: weight)
}

func drawText(_ ctx: CGContext, _ text: String, in rect: CGRect, size: CGFloat,
             color: NSColor = ink, weight: NSFont.Weight = .regular,
             alignment: NSTextAlignment = .left, mono: Bool = false,
             lineSpacing: CGFloat = 2) -> CGFloat {
    guard !text.isEmpty else { return 0 }
    let style = NSMutableParagraphStyle()
    style.alignment = alignment
    style.lineSpacing = lineSpacing
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font(size, weight: weight, mono: mono),
        .foregroundColor: color,
        .paragraphStyle: style
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let setter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
    let constraint = CGSize(width: rect.width, height: .greatestFiniteMagnitude)
    let measured = CTFramesetterSuggestFrameSizeWithConstraints(
        setter, CFRange(location: 0, length: attributed.length), nil, constraint, nil
    )
    let path = CGPath(rect: rect, transform: nil)
    let frame = CTFramesetterCreateFrame(
        setter, CFRange(location: 0, length: attributed.length), path, nil
    )
    // The page context is top-left-oriented for layout, while CoreText draws
    // in a bottom-left-oriented coordinate system. Reflect only this text
    // frame around its own bounds so glyphs remain upright.
    ctx.saveGState()
    ctx.translateBy(x: 0, y: rect.minY + rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    CTFrameDraw(frame, ctx)
    ctx.restoreGState()
    return ceil(measured.height)
}

func fill(_ ctx: CGContext, _ rect: CGRect, _ color: NSColor, radius: CGFloat = 18) {
    ctx.setFillColor(color.cgColor)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.fillPath()
}

func outline(_ ctx: CGContext, _ rect: CGRect, _ color: NSColor = line, radius: CGFloat = 18, width: CGFloat = 1) {
    ctx.setStrokeColor(color.cgColor)
    ctx.setLineWidth(width)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.strokePath()
}

func cardBox(_ ctx: CGContext, _ rect: CGRect, fillColor: NSColor = card, radius: CGFloat = 18) {
    fill(ctx, rect, fillColor, radius: radius)
    outline(ctx, rect, line, radius: radius)
}

func drawLogo(_ ctx: CGContext, x: CGFloat, y: CGFloat, width: CGFloat) {
    guard let image = NSImage(contentsOfFile: logoPath),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
    let height = width * CGFloat(cgImage.height) / CGFloat(cgImage.width)
    let rect = CGRect(x: x, y: y, width: width, height: height)
    ctx.saveGState()
    ctx.translateBy(x: 0, y: rect.minY + rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(cgImage, in: rect)
    ctx.restoreGState()
}

func drawImage(_ ctx: CGContext, path: String, in rect: CGRect, radius: CGFloat = 16) {
    guard let image = NSImage(contentsOfFile: path),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
    let imageRatio = CGFloat(cgImage.width) / CGFloat(cgImage.height)
    let rectRatio = rect.width / rect.height
    let fitted: CGRect
    if imageRatio > rectRatio {
        let height = rect.width / imageRatio
        fitted = CGRect(x: rect.minX, y: rect.minY + (rect.height - height) / 2, width: rect.width, height: height)
    } else {
        let width = rect.height * imageRatio
        fitted = CGRect(x: rect.minX + (rect.width - width) / 2, y: rect.minY, width: width, height: rect.height)
    }
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    ctx.saveGState()
    ctx.translateBy(x: 0, y: fitted.minY + fitted.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(cgImage, in: fitted)
    ctx.restoreGState()
    ctx.restoreGState()
    outline(ctx, rect, line, radius: radius)
}

func header(_ ctx: CGContext, section: String, page: Int, total: Int, footer: String) {
    drawLogo(ctx, x: margin, y: 30, width: 142)
    drawText(ctx: ctx, section.uppercased(), x: 400, y: 42, width: 160, size: 9, color: quiet, weight: .bold, alignment: .right)
    ctx.setStrokeColor(line.cgColor)
    ctx.setLineWidth(0.8)
    ctx.move(to: CGPoint(x: margin, y: 742))
    ctx.addLine(to: CGPoint(x: pageWidth - margin, y: 742))
    ctx.strokePath()
    drawText(ctx: ctx, footer, x: margin, y: 753, width: 300, size: 8, color: quiet, weight: .bold)
    drawText(ctx: ctx, "\(page) / \(total)", x: 520, y: 753, width: 40, size: 8, color: quiet, weight: .bold, alignment: .right)
}

func drawText(ctx: CGContext, _ text: String, x: CGFloat, y: CGFloat, width: CGFloat,
              size: CGFloat, color: NSColor = ink, weight: NSFont.Weight = .regular,
              alignment: NSTextAlignment = .left, mono: Bool = false, lineSpacing: CGFloat = 2) {
    _ = drawText(ctx, text, in: CGRect(x: x, y: y, width: width, height: 700), size: size,
                 color: color, weight: weight, alignment: alignment, mono: mono, lineSpacing: lineSpacing)
}

func number(_ ctx: CGContext, _ value: String, x: CGFloat, y: CGFloat, size: CGFloat = 14) {
    fill(ctx, CGRect(x: x, y: y, width: 32, height: 32), green, radius: 16)
    drawText(ctx: ctx, value, x: x, y: y + 8, width: 32, size: size, color: .white, weight: .bold, alignment: .center)
}

func pill(_ ctx: CGContext, _ text: String, x: CGFloat, y: CGFloat, width: CGFloat, color: NSColor = greenSoft) {
    fill(ctx, CGRect(x: x, y: y, width: width, height: 30), color, radius: 15)
    drawText(ctx: ctx, text, x: x + 8, y: y + 8, width: width - 16, size: 9, color: green, weight: .bold, alignment: .center, mono: text.contains("http") || text.contains("\\"))
}

func miniStep(_ ctx: CGContext, _ n: String, _ title: String, _ detail: String, x: CGFloat, y: CGFloat, width: CGFloat) {
    cardBox(ctx, CGRect(x: x, y: y, width: width, height: 92))
    number(ctx, n, x: x + 18, y: y + 30, size: 13)
    drawText(ctx: ctx, title, x: x + 64, y: y + 23, width: width - 82, size: 13, weight: .bold)
    drawText(ctx: ctx, detail, x: x + 64, y: y + 48, width: width - 82, size: 10, color: muted, lineSpacing: 1)
}

func drawQR(_ ctx: CGContext, x: CGFloat, y: CGFloat, size: CGFloat) {
    fill(ctx, CGRect(x: x, y: y, width: size, height: size), NSColor(calibratedWhite: 0.06, alpha: 1), radius: 10)
    let cells = [
        "1110111", "1010101", "1110111", "0001010", "1110101", "1011111", "1110011"
    ]
    let cell = size / 9
    ctx.setFillColor(NSColor.white.cgColor)
    for row in 0..<cells.count {
        for (col, char) in cells[row].enumerated() where char == "1" {
            ctx.fill(CGRect(x: x + cell + CGFloat(col) * cell, y: y + cell + CGFloat(row) * cell, width: cell * 0.82, height: cell * 0.82))
        }
    }
}

func drawAndroidPage(_ ctx: CGContext, _ page: Int) {
    if page == 1 {
        drawLogo(ctx, x: margin, y: 32, width: 200)
        pill(ctx, "ANDROID WALKTHROUGH", x: margin, y: 132, width: 140)
        drawText(ctx: ctx, "Talk on your phone.\nType on your computer.", x: margin, y: 185, width: 510, size: 31, weight: .bold, lineSpacing: 2)
        drawText(ctx: ctx, "A clean five-step setup for Wispr Flow, Tailscale, and Whisper Bridge. Pair once, then send dictated text to your Mac, Ubuntu, or Windows computer.", x: margin, y: 282, width: 470, size: 13, color: muted, lineSpacing: 4)
        let box = CGRect(x: margin, y: 370, width: pageWidth - margin * 2, height: 180)
        cardBox(ctx, box, radius: 22)
        drawText(ctx: ctx, "THE SIMPLE VERSION", x: box.minX + 24, y: box.minY + 22, width: 200, size: 10, color: muted, weight: .bold)
        let xs: [CGFloat] = [box.minX + 45, box.midX, box.maxX - 45]
        for i in 0..<3 {
            number(ctx, "\(i + 1)", x: xs[i] - 16, y: box.minY + 68)
        }
        ctx.setStrokeColor(line.cgColor); ctx.setLineWidth(1.5)
        ctx.move(to: CGPoint(x: xs[0] + 22, y: box.minY + 84)); ctx.addLine(to: CGPoint(x: xs[1] - 22, y: box.minY + 84)); ctx.strokePath()
        ctx.move(to: CGPoint(x: xs[1] + 22, y: box.minY + 84)); ctx.addLine(to: CGPoint(x: xs[2] - 22, y: box.minY + 84)); ctx.strokePath()
        let labels = [("Speak", "Wispr Flow"), ("Share", "Whisper Bridge"), ("Type", "Your computer")]
        for i in 0..<3 {
            drawText(ctx: ctx, labels[i].0, x: xs[i] - 52, y: box.minY + 112, width: 104, size: 13, weight: .bold, alignment: .center)
            drawText(ctx: ctx, labels[i].1, x: xs[i] - 58, y: box.minY + 132, width: 116, size: 9, color: muted, alignment: .center)
        }
        fill(ctx, CGRect(x: box.minX + 24, y: box.maxY - 30, width: box.width - 48, height: 22), greenSoft, radius: 11)
        drawText(ctx: ctx, "Secure anywhere with Tailscale. No port forwarding.", x: box.minX + 34, y: box.maxY - 25, width: box.width - 68, size: 9, color: green, weight: .bold, alignment: .center)
        drawText(ctx: ctx, "Unofficial companion for Wispr Flow. No Wispr Flow subscription or Tailscale account is included.", x: margin, y: 620, width: 500, size: 9, color: quiet)
        drawText(ctx: ctx, "whisperbridge.app  |  Open source setup guide", x: margin, y: 678, width: 400, size: 9, color: muted, weight: .bold)
        return
    }
    header(ctx, section: ["", "BEFORE YOU START", "COMPUTER SETUP", "SECURE PAIRING", "YOUR DAILY FLOW"][page - 1], page: page, total: 5, footer: "WHISPER BRIDGE  |  ANDROID WALKTHROUGH")
    if page == 2 {
        drawText(ctx: ctx, "Install the three pieces.", x: margin, y: 100, width: 500, size: 27, weight: .bold)
        drawText(ctx: ctx, "Set these up once. The rest of this guide connects them together.", x: margin, y: 143, width: 500, size: 13, color: muted)
        miniStep(ctx, "1", "Wispr Flow", "Voice dictation on your Android phone. Finish onboarding first.", x: margin, y: 205, width: 242)
        miniStep(ctx, "2", "Tailscale", "Sign in to the same tailnet on your phone and computer.", x: 318, y: 205, width: 242)
        cardBox(ctx, CGRect(x: margin, y: 320, width: 508, height: 112))
        number(ctx, "3", x: margin + 20, y: 360)
        drawText(ctx: ctx, "Whisper Bridge", x: margin + 68, y: 342, width: 220, size: 15, weight: .bold)
        drawText(ctx: ctx, "Install the Android APK and the matching receiver ZIP.", x: margin + 68, y: 371, width: 390, size: 11, color: muted)
        pill(ctx, "OPEN GITHUB RELEASES", x: margin + 68, y: 395, width: 145)
        fill(ctx, CGRect(x: margin, y: 470, width: 508, height: 132), greenSoft, radius: 18)
        drawText(ctx: ctx, "Before moving on", x: margin + 22, y: 492, width: 250, size: 13, color: green, weight: .bold)
        let checks = ["Wispr Flow creates text when you dictate.", "Tailscale says Connected on both devices.", "The receiver ZIP is downloaded for your computer."]
        for i in 0..<3 {
            fill(ctx, CGRect(x: margin + 24, y: 527 + CGFloat(i) * 24, width: 8, height: 8), green, radius: 4)
            drawText(ctx: ctx, checks[i], x: margin + 45, y: 521 + CGFloat(i) * 24, width: 430, size: 10, color: ink)
        }
        drawText(ctx: ctx, "Tip: Tailscale is optional on trusted home Wi-Fi, but recommended for every remote connection.", x: margin, y: 635, width: 510, size: 9, color: muted)
    } else if page == 3 {
        drawText(ctx: ctx, "Prepare your computer.", x: margin, y: 100, width: 500, size: 27, weight: .bold)
        drawText(ctx: ctx, "The receiver runs locally, accepts your paired phone, and places text in the field you selected.", x: margin, y: 143, width: 500, size: 12, color: muted)
        let names = [("macOS", "DOUBLE-CLICK", "mac-server/install.command", "Approve Accessibility."), ("Ubuntu", "RUN", "./ubuntu-server/install.sh", "Creates a user service."), ("Windows", "RUN IN POWERSHELL", "windows-server\\install.ps1", "Python 3.12+; no console windows in v1.3.")]
        for i in 0..<3 {
            let x = margin + CGFloat(i) * 172
            cardBox(ctx, CGRect(x: x, y: 205, width: 158, height: 172))
            drawText(ctx: ctx, names[i].0, x: x + 18, y: 226, width: 122, size: 15, weight: .bold)
            drawText(ctx: ctx, names[i].1, x: x + 18, y: 263, width: 122, size: 8, color: muted, weight: .bold)
            pill(ctx, names[i].2, x: x + 14, y: 290, width: 130, color: NSColor(calibratedWhite: 0.94, alpha: 1))
            drawText(ctx: ctx, names[i].3, x: x + 18, y: 336, width: 122, size: 9, color: muted, lineSpacing: 1)
        }
        cardBox(ctx, CGRect(x: margin, y: 410, width: 508, height: 92))
        number(ctx, "1", x: margin + 18, y: 440)
        drawText(ctx: ctx, "Open the receiver console", x: margin + 64, y: 430, width: 370, size: 13, weight: .bold)
        drawText(ctx: ctx, "Visit http://localhost:9877 in a browser on the computer.", x: margin + 64, y: 456, width: 400, size: 10, color: muted)
        fill(ctx, CGRect(x: margin, y: 535, width: 508, height: 85), greenSoft, radius: 18)
        drawText(ctx: ctx, "Permission and focus", x: margin + 22, y: 554, width: 250, size: 13, color: green, weight: .bold)
        drawText(ctx: ctx, "macOS needs Accessibility permission. On every platform, click the destination text field before sending.", x: margin + 22, y: 581, width: 460, size: 10, color: ink)
        drawText(ctx: ctx, "Keep the receiver running. macOS uses a login item; Ubuntu and Windows start at sign-in.", x: margin, y: 655, width: 510, size: 9, color: muted)
    } else if page == 4 {
        drawText(ctx: ctx, "Pair once. Use anywhere.", x: margin, y: 100, width: 500, size: 27, weight: .bold)
        drawText(ctx: ctx, "Use the receiver's Tailscale pairing QR. It carries the private host, port, and token.", x: margin, y: 143, width: 500, size: 12, color: muted)
        cardBox(ctx, CGRect(x: margin, y: 205, width: 225, height: 260))
        drawText(ctx: ctx, "ON YOUR ANDROID", x: margin + 20, y: 225, width: 185, size: 9, color: muted, weight: .bold)
        let pairSteps = ["Open Whisper Bridge and tap the gear.", "Tap Scan and scan the Tailscale QR.", "Tap Test, then Save."]
        for i in 0..<3 {
            number(ctx, "\(i + 1)", x: margin + 20, y: 267 + CGFloat(i) * 56, size: 12)
            drawText(ctx: ctx, pairSteps[i], x: margin + 64, y: 272 + CGFloat(i) * 56, width: 142, size: 10, color: ink, lineSpacing: 1)
        }
        cardBox(ctx, CGRect(x: 300, y: 205, width: 260, height: 260))
        drawText(ctx: ctx, "ON YOUR COMPUTER", x: 324, y: 225, width: 210, size: 9, color: muted, weight: .bold)
        drawQR(ctx, x: 326, y: 270, size: 126)
        drawText(ctx: ctx, "Receiver console", x: 470, y: 290, width: 70, size: 10, weight: .bold)
        drawText(ctx: ctx, "Select the Tailscale QR at localhost:9877.", x: 470, y: 320, width: 70, size: 8, color: muted, lineSpacing: 1)
        fill(ctx, CGRect(x: margin, y: 505, width: 508, height: 82), amberSoft, radius: 18)
        drawText(ctx: ctx, "No camera scan?", x: margin + 22, y: 524, width: 200, size: 13, color: NSColor(calibratedRed: 0.55, green: 0.35, blue: 0.05, alpha: 1), weight: .bold)
        drawText(ctx: ctx, "Use Paste pairing link in Settings and paste the link copied from the receiver console.", x: margin + 22, y: 552, width: 460, size: 10, color: ink)
        drawText(ctx: ctx, "Keep Tailscale Funnel off. Whisper Bridge should stay private to your tailnet.", x: margin, y: 630, width: 510, size: 9, color: muted)
    } else {
        drawText(ctx: ctx, "Dictate. Share. Type.", x: margin, y: 100, width: 500, size: 27, weight: .bold)
        drawText(ctx: ctx, "Once paired, this is the whole routine. Switch profiles at the top whenever you want another computer.", x: margin, y: 143, width: 510, size: 12, color: muted)
        let flow = [("Dictate", "Speak into Wispr Flow."), ("Share", "Use Android's Share action, then choose Whisper Bridge."), ("Select", "Choose the target computer profile at the top."), ("Focus", "Click the destination text field on the computer."), ("Send", "Tap Type. Use Enter for Return or Clipboard for copy only.")]
        for i in 0..<5 {
            let y = 205 + CGFloat(i) * 62
            cardBox(ctx, CGRect(x: margin, y: y, width: 508, height: 48), radius: 16)
            number(ctx, "\(i + 1)", x: margin + 14, y: y + 8, size: 11)
            drawText(ctx: ctx, flow[i].0, x: margin + 66, y: y + 14, width: 82, size: 11, weight: .bold)
            drawText(ctx: ctx, flow[i].1, x: margin + 148, y: y + 14, width: 330, size: 10, color: muted)
        }
        fill(ctx, CGRect(x: margin, y: 535, width: 508, height: 130), greenSoft, radius: 18)
        drawText(ctx: ctx, "Quick fixes", x: margin + 22, y: 553, width: 180, size: 13, color: green, weight: .bold)
        let fixes = [("Test fails", "Confirm Tailscale is connected on both devices and scan the QR again."), ("No text appears", "Click the destination field first; on macOS, recheck Accessibility."), ("No share option", "Reinstall Whisper Bridge, then check Android's More menu.")]
        for i in 0..<3 {
            let y = 584 + CGFloat(i) * 24
            drawText(ctx: ctx, fixes[i].0 + ":", x: margin + 22, y: y, width: 104, size: 9, weight: .bold)
            drawText(ctx: ctx, fixes[i].1, x: margin + 132, y: y, width: 350, size: 9, color: ink)
        }
        drawText(ctx: ctx, "Need more help? github.com/BrandonKNguyen192/whisperflow-bridge", x: margin, y: 690, width: 510, size: 9, color: muted)
    }
}

func drawIOSPage(_ ctx: CGContext, _ page: Int, mainLight: String, settings: String) {
    let sections = ["", "BEFORE YOU START", "PAIR YOUR COMPUTER", "COMPOSE AND SEND", "TRACKPAD + AIR MOUSE"]
    if page == 1 {
        drawLogo(ctx, x: margin, y: 32, width: 200)
        pill(ctx, "IPHONE / IPAD WALKTHROUGH", x: margin, y: 132, width: 170)
        drawText(ctx: ctx, "Your phone.\nYour keyboard.", x: margin, y: 185, width: 510, size: 31, weight: .bold, lineSpacing: 2)
        drawText(ctx: ctx, "A native iOS setup for Whisper Bridge: pair a computer, send text, steer its cursor, and use the iPhone as an air mouse.", x: margin, y: 282, width: 470, size: 13, color: muted, lineSpacing: 4)
        cardBox(ctx, CGRect(x: margin, y: 370, width: pageWidth - margin * 2, height: 180), radius: 22)
        drawText(ctx: ctx, "THE SIMPLE VERSION", x: margin + 24, y: 392, width: 200, size: 10, color: muted, weight: .bold)
        let labels = [("Pair", "Scan or paste"), ("Compose", "Type / Enter / Copy"), ("Control", "Trackpad + air mouse")]
        let xs: [CGFloat] = [margin + 45, pageWidth / 2, pageWidth - margin - 45]
        for i in 0..<3 {
            number(ctx, "\(i + 1)", x: xs[i] - 16, y: 438)
            drawText(ctx: ctx, labels[i].0, x: xs[i] - 58, y: 482, width: 116, size: 13, weight: .bold, alignment: .center)
            drawText(ctx: ctx, labels[i].1, x: xs[i] - 65, y: 508, width: 130, size: 9, color: muted, alignment: .center)
        }
        ctx.setStrokeColor(line.cgColor); ctx.setLineWidth(1.5)
        ctx.move(to: CGPoint(x: xs[0] + 22, y: 454)); ctx.addLine(to: CGPoint(x: xs[1] - 22, y: 454)); ctx.strokePath()
        ctx.move(to: CGPoint(x: xs[1] + 22, y: 454)); ctx.addLine(to: CGPoint(x: xs[2] - 22, y: 454)); ctx.strokePath()
        fill(ctx, CGRect(x: margin + 24, y: 570, width: 508, height: 28), greenSoft, radius: 14)
        drawText(ctx: ctx, "iOS 26+  |  Liquid Glass  |  Tailscale-ready  |  iPhone + iPad", x: margin + 34, y: 578, width: 488, size: 9, color: green, weight: .bold, alignment: .center)
        drawText(ctx: ctx, "iOS is currently a signed preview build. The desktop receiver protocol is shared with Android.", x: margin, y: 650, width: 510, size: 9, color: quiet)
        drawText(ctx: ctx, "whisperbridge.app  |  Open source setup guide", x: margin, y: 690, width: 400, size: 9, color: muted, weight: .bold)
        return
    }
    header(ctx, section: sections[page - 1], page: page, total: 5, footer: "WHISPER BRIDGE  |  IPHONE WALKTHROUGH")
    if page == 2 {
        drawText(ctx: ctx, "Install the three pieces.", x: margin, y: 100, width: 500, size: 27, weight: .bold)
        drawText(ctx: ctx, "The iOS app is the controller. Your computer runs the receiver; Tailscale makes the path private.", x: margin, y: 143, width: 500, size: 12, color: muted)
        miniStep(ctx, "1", "Whisper Bridge iOS", "Install the signed preview on iPhone or iPad.", x: margin, y: 205, width: 242)
        miniStep(ctx, "2", "Tailscale", "Sign in to the same tailnet on phone and computer.", x: 318, y: 205, width: 242)
        cardBox(ctx, CGRect(x: margin, y: 320, width: 508, height: 112))
        number(ctx, "3", x: margin + 20, y: 360)
        drawText(ctx: ctx, "Desktop receiver", x: margin + 68, y: 342, width: 220, size: 15, weight: .bold)
        drawText(ctx: ctx, "Install the Mac, Ubuntu, or Windows ZIP from GitHub Releases.", x: margin + 68, y: 371, width: 390, size: 11, color: muted)
        pill(ctx, "OPEN RELEASES", x: margin + 68, y: 395, width: 115)
        fill(ctx, CGRect(x: margin, y: 470, width: 508, height: 132), greenSoft, radius: 18)
        drawText(ctx: ctx, "Before moving on", x: margin + 22, y: 492, width: 250, size: 13, color: green, weight: .bold)
        let checks = ["iPhone/iPad is on iOS 26 or later.", "Tailscale shows Connected on both devices.", "The receiver console opens at localhost:9877."]
        for i in 0..<3 {
            fill(ctx, CGRect(x: margin + 24, y: 527 + CGFloat(i) * 24, width: 8, height: 8), green, radius: 4)
            drawText(ctx: ctx, checks[i], x: margin + 45, y: 521 + CGFloat(i) * 24, width: 430, size: 10, color: ink)
        }
        drawText(ctx: ctx, "Tailscale is optional on trusted home Wi-Fi, but recommended for remote use.", x: margin, y: 635, width: 510, size: 9, color: muted)
    } else if page == 3 {
        drawText(ctx: ctx, "Pair your computer.", x: margin, y: 100, width: 500, size: 27, weight: .bold)
        drawText(ctx: ctx, "Scan the receiver QR, or paste its pairing link. The link includes the private host, port, and token.", x: margin, y: 143, width: 285, size: 12, color: muted)
        drawImage(ctx, path: settings, in: CGRect(x: 350, y: 180, width: 190, height: 485), radius: 22)
        let steps = [("Install receiver", "Open the computer's local console."), ("Open Settings", "Tap the gear in Whisper Bridge."), ("Scan or paste", "Use Scan for the QR, or Paste pairing link."), ("Test and save", "Confirm Connected, then tap Save.")]
        for i in 0..<4 {
            let y = 228 + CGFloat(i) * 92
            number(ctx, "\(i + 1)", x: margin, y: y, size: 12)
            drawText(ctx: ctx, steps[i].0, x: margin + 48, y: y + 3, width: 240, size: 12, weight: .bold)
            drawText(ctx: ctx, steps[i].1, x: margin + 48, y: y + 27, width: 250, size: 10, color: muted)
        }
        fill(ctx, CGRect(x: margin, y: 610, width: 270, height: 60), amberSoft, radius: 16)
        drawText(ctx: ctx, "No camera scan? Paste the pairing link from the receiver console.", x: margin + 16, y: 628, width: 238, size: 9, color: ink)
    } else if page == 4 {
        drawText(ctx: ctx, "Compose and send.", x: margin, y: 100, width: 500, size: 27, weight: .bold)
        drawText(ctx: ctx, "The compose screen keeps the fast path close: choose a profile, enter text, and send it to the focused field.", x: margin, y: 143, width: 500, size: 12, color: muted)
        drawImage(ctx, path: mainLight, in: CGRect(x: margin, y: 205, width: 230, height: 500), radius: 22)
        let steps = [("Choose", "Tap MacBook Pro, Mac Studio, or another profile."), ("Write", "Type or paste in the compose field."), ("Type", "Tap Type to paste into the focused computer field."), ("Return", "Tap Enter, or enable Enter after typing."), ("Copy", "Tap Copy to update the computer clipboard only.")]
        for i in 0..<5 {
            let y = 235 + CGFloat(i) * 78
            number(ctx, "\(i + 1)", x: 330, y: y, size: 12)
            drawText(ctx: ctx, steps[i].0, x: 378, y: y + 3, width: 140, size: 12, weight: .bold)
            drawText(ctx: ctx, steps[i].1, x: 378, y: y + 27, width: 165, size: 9, color: muted, lineSpacing: 1)
        }
    } else {
        drawText(ctx: ctx, "Trackpad + air mouse.", x: margin, y: 100, width: 500, size: 27, weight: .bold)
        drawText(ctx: ctx, "Use the phone as a remote pointer when your hands are away from the computer.", x: margin, y: 143, width: 500, size: 12, color: muted)
        drawImage(ctx, path: mainLight, in: CGRect(x: 350, y: 190, width: 190, height: 440), radius: 22)
        let features = [("Trackpad", "Drag to move. Tap to click. Hold to drag. Two fingers scroll."), ("Air mouse", "Press and hold the Air mouse button, then tilt the phone to steer."), ("Sensitivity", "Tune the speed in Settings; invert direction if the motion feels backward."), ("Safety", "Release the button to stop gyro control immediately.")]
        for i in 0..<4 {
            let y = 220 + CGFloat(i) * 88
            cardBox(ctx, CGRect(x: margin, y: y, width: 265, height: 68), radius: 16)
            drawText(ctx: ctx, features[i].0, x: margin + 16, y: y + 14, width: 220, size: 11, color: green, weight: .bold)
            drawText(ctx: ctx, features[i].1, x: margin + 16, y: y + 35, width: 230, size: 9, color: muted, lineSpacing: 1)
        }
        fill(ctx, CGRect(x: margin, y: 610, width: 508, height: 58), greenSoft, radius: 16)
        drawText(ctx: ctx, "If the cursor does not move, click a target field first and confirm the receiver has mouse permissions.", x: margin + 18, y: 628, width: 472, size: 9, color: ink)
    }
}

func writePDF(path: String, pageCount: Int, drawPage: (CGContext, Int) -> Void) {
    let url = URL(fileURLWithPath: path)
    var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
    guard let consumer = CGDataConsumer(url: url as CFURL),
          let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        fatalError("Could not create PDF context: \(path)")
    }
    for page in 1...pageCount {
        ctx.beginPDFPage(nil)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: pageHeight)
        ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(pageBackground.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        drawPage(ctx, page)
        ctx.restoreGState()
        ctx.endPDFPage()
    }
    ctx.closePDF()
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let androidPDF = output.appendingPathComponent("whisper-bridge-android-walkthrough.pdf").path
writePDF(path: androidPDF, pageCount: 5) { ctx, page in drawAndroidPage(ctx, page) }

let iOSMainLight = root.appendingPathComponent("documentation/screenshots/ios-walkthrough-main-light.png").path
let iOSMainDark = root.appendingPathComponent("documentation/screenshots/ios-walkthrough-main-dark.png").path
let iOSSettings = root.appendingPathComponent("documentation/screenshots/ios-walkthrough-settings-earth.png").path
let iosPDF = output.appendingPathComponent("whisper-bridge-iphone-walkthrough.pdf").path
writePDF(path: iosPDF, pageCount: 5) { ctx, page in
    drawIOSPage(ctx, page, mainLight: iOSMainLight, settings: iOSSettings)
}

print("Generated \(androidPDF)")
print("Generated \(iosPDF)")
