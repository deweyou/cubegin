import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
let root = URL(fileURLWithPath: CommandLine.arguments[1])
func bitmap(_ width: Int, _ height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func save(_ context: CGContext, _ path: String) {
    let target = root.appendingPathComponent(path)
    try! FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))
}
let mark = bitmap(240, 240)
mark.translateBy(x: 0, y: 240)
mark.scaleBy(x: 240 / 68.0, y: -240 / 68.0)
mark.translateBy(x: -16, y: -16)
for (x,y,r,color) in [(22.0,22.0,7.0,0xffc62e),(50,22,7,0xec3b3b),(22,50,7,0x1eb877),(50,50,8,0x2f7ce0)] {
    mark.setFillColor(red: CGFloat((color >> 16) & 255) / 255, green: CGFloat((color >> 8) & 255) / 255, blue: CGFloat(color & 255) / 255, alpha: 1)
    mark.addPath(CGPath(roundedRect: CGRect(x: x,y: y,width: 28,height: 28), cornerWidth: r, cornerHeight: r, transform: nil))
    mark.fillPath()
}
save(mark,"Cubegin/Assets.xcassets/LaunchMark.imageset/launch-mark@3x.png")
for dark in [false, true] {
    let source = try String(contentsOf: root.appendingPathComponent("Design/LegacyIcons/brand/svg/cubegin-wordmark\(dark ? "-dark" : "").svg"), encoding: .utf8)
    let regex = try NSRegularExpression(pattern: #"<path d="([^"]+)""#)
    let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source))!
    let d = String(source[Range(match.range(at: 1), in: source)!])
    let tokenRegex = try NSRegularExpression(pattern: #"[MLQZ]|-?(?:\d*\.)?\d+(?:[eE][-+]?\d+)?"#)
    let tokens = tokenRegex.matches(in: d, range: NSRange(d.startIndex..., in: d)).map { String(d[Range($0.range,in:d)!]) }
    var index = 0
    func point() -> CGPoint { let p = CGPoint(x: Double(tokens[index])!, y: Double(tokens[index+1])!); index += 2; return p }
    let path = CGMutablePath()
    while index < tokens.count {
        let command=tokens[index]; index += 1
        switch command {
        case "M": path.move(to: point())
        case "L": path.addLine(to: point())
        case "Q": let control=point(); path.addQuadCurve(to: point(), control: control)
        case "Z": path.closeSubpath()
        default: fatalError("Unsupported SVG command \(command)")
        }
    }
    let context=bitmap(324, 91)
    context.translateBy(x:0, y:91)
    context.scaleBy(x:324/350.8, y: -91/97.7)
    context.translateBy(x: -0.6, y: 74.3)
    context.addPath(path)
    context.setFillColor(red: dark ? 1 : 27/255.0, green: dark ? 1 : 32/255.0, blue: dark ? 1 : 48/255.0, alpha: 1)
    context.fillPath()
    save(context,"Cubegin/Assets.xcassets/LaunchWordmark.imageset/wordmark\(dark ? "-dark" : "")@3x.png")
}
