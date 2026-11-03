// 生成 AppIcon.icns 的各尺寸 PNG。图标语言跟菜单栏那颗点一致：深色圆角方块 + 绿点 + 绿环。
// 用法：swift tools/make_icon.swift <输出目录>   （由 tools/make_app.sh 调用）
import AppKit
import Foundation

let argDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try? FileManager.default.createDirectory(atPath: argDir, withIntermediateDirectories: true)

/// 一个尺寸画一遍，坐标全部按边长比例算，所以 16pt 与 1024pt 是同一个图形。
func writePNG(side: Int, to path: String) {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0),
          let ctx = CGContext(data: rep.bitmapData, width: side, height: side,
                              bitsPerComponent: 8, bytesPerRow: rep.bytesPerRow,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("can't allocate \(side)px bitmap") }

    let s = CGFloat(side)
    let u = s / 1024.0                      // 一切尺寸按 1024 网格取比例
    ctx.setFillColor(NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.21, alpha: 1).cgColor)
    let inset = 110 * u
    let tile = CGRect(x: inset, y: inset, width: s - 220 * u, height: s - 220 * u)
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: 190 * u, cornerHeight: 190 * u, transform: nil))
    ctx.fillPath()

    let green = NSColor(calibratedRed: 0.30, green: 0.78, blue: 0.42, alpha: 1).cgColor
    let c = CGPoint(x: s / 2, y: s / 2)
    // 环：跟"未取到数据"那一态同一个开口圆环
    ctx.setStrokeColor(green)
    ctx.setLineWidth(78 * u)
    ctx.addArc(center: c, radius: 250 * u, startAngle: 0.6, endAngle: 0.6 + .pi * 2 * 0.78,
               clockwise: false)
    ctx.drawPath(using: .stroke)
    // 点：空闲态那颗实心点
    ctx.setFillColor(green)
    ctx.fillEllipse(in: CGRect(x: c.x - 96 * u, y: c.y - 96 * u, width: 192 * u, height: 192 * u))

    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
    try! png.write(to: URL(fileURLWithPath: path))
}

let sizes: [(name: String, side: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for e in sizes { writePNG(side: e.side, to: "\(argDir)/\(e.name)") }
print("wrote \(sizes.count) png into \(argDir)")
