#!/usr/bin/env swift
// 把 docs/ref 里的透明底原图裁掉多余留白、按 macOS 规范重排成 .iconset
// 用法：swift scripts/make-icon.swift <源图> <输出 .iconset 目录>
import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("用法：swift scripts/make-icon.swift <源图 png> <输出 .iconset 目录>")
    exit(1)
}
let sourcePath = arguments[1]
let outputDir = arguments[2]

guard let source = NSImage(contentsOfFile: sourcePath),
      let tiff = source.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff) else {
    print("读取源图失败：\(sourcePath)")
    exit(1)
}

// 1. 找出「实心图案」的包围盒（alpha ≥ 128），忽略外围投影
let width = rep.pixelsWide
let height = rep.pixelsHigh
var minX = width, minY = height, maxX = 0, maxY = 0
for y in 0..<height {
    for x in 0..<width {
        guard let color = rep.colorAt(x: x, y: y), color.alphaComponent >= 0.5 else { continue }
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }
}
guard maxX > minX, maxY > minY else {
    print("源图没有可见图案（全透明？）")
    exit(1)
}
let artSide = CGFloat(max(maxX - minX, maxY - minY) + 1)
print("图案包围盒：\(maxX - minX + 1)x\(maxY - minY + 1)，画布 \(width)x\(height)")

// 2. 合成 1024 主图：图案占 824（Apple 模板的 80%），其余留作安全边距
let master = 1024
let artTarget: CGFloat = 824
let scale = artTarget / artSide
let drawSide = CGFloat(max(width, height)) * scale
let origin = CGPoint(x: (CGFloat(master) - drawSide) / 2, y: (CGFloat(master) - drawSide) / 2)

guard let ctx = CGContext(
    data: nil,
    width: master,
    height: master,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    print("创建绘图上下文失败")
    exit(1)
}
ctx.interpolationQuality = .high
guard let cgSource = rep.cgImage else {
    print("取 CGImage 失败")
    exit(1)
}
ctx.draw(cgSource, in: CGRect(x: origin.x, y: origin.y, width: drawSide, height: drawSide))

guard let masterImage = ctx.makeImage() else {
    print("生成主图失败")
    exit(1)
}

// 3. 输出 .iconset 需要的全部尺寸
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

let variants: [(name: String, size: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    guard let small = CGContext(
        data: nil,
        width: variant.size,
        height: variant.size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { continue }
    small.interpolationQuality = .high
    small.draw(masterImage, in: CGRect(x: 0, y: 0, width: variant.size, height: variant.size))
    guard let cgSmall = small.makeImage() else { continue }
    let bitmap = NSBitmapImageRep(cgImage: cgSmall)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { continue }
    let path = "\(outputDir)/\(variant.name).png"
    try png.write(to: URL(fileURLWithPath: path))
}

print("已输出 \(variants.count) 个尺寸到 \(outputDir)")
