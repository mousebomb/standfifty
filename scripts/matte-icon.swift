#!/usr/bin/env swift
// 把「白底 + 实心圆盘」的图抠成透明底，并重排到 macOS 图标规范的 1024 画布。
// 用法：swift scripts/matte-icon.swift <源图> <输出 png>
//
// 做法：用饱和度找出圆盘的外接方框 → 按圆盘外缘做半径渐隐的 alpha 遮罩。
// 这样能连同白底和外部烘焙投影一起去掉，保留圆盘自己的高光边。
// TODO: 目前假设主体是居中实心圆盘；换成 squircle 底时要改这里的裁切方式。
import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("用法：swift scripts/matte-icon.swift <源图> <输出 png>")
    exit(1)
}
let sourcePath = arguments[1]
let outputPath = arguments[2]

guard let source = NSImage(contentsOfFile: sourcePath),
      let tiff = source.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff) else {
    print("读取源图失败：\(sourcePath)")
    exit(1)
}
let width = rep.pixelsWide
let height = rep.pixelsHigh

// 1. 找圆盘：蓝盘的特征是蓝 > 红且有明显饱和度，能避开白底和灰色投影
var minX = width, maxX = 0, minY = height, maxY = 0
for y in stride(from: 0, to: height, by: 2) {
    for x in stride(from: 0, to: width, by: 2) {
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        if c.blueComponent - c.redComponent > 0.12 && c.greenComponent - c.redComponent > 0.05 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
guard maxX > minX, maxY > minY else {
    print("没找到圆形主体（需要高饱和度的圆盘）")
    exit(1)
}

let centerX = CGFloat(minX + maxX) / 2
let centerY = CGFloat(minY + maxY) / 2
// 外缘稍稍外扩，保住圆盘最外层的高光边
let radius = CGFloat(max(maxX - minX, maxY - minY)) / 2 + 1

// 2. 排版：图案占 1024 画布 80%（824），符合 macOS 模板
let master = 1024
let artTarget: CGFloat = 824
let scale = (artTarget / 2) / radius
let drawSide = CGFloat(max(width, height)) * scale

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

// 让源图的圆盘中心落在画布中心
let screenCenter = CGFloat(master) / 2
let originX = screenCenter - centerX * scale
// CGContext 原点在左下，位图坐标原点在左上，Y 需要翻一次
let originY = screenCenter - (CGFloat(height) - centerY) * scale
ctx.draw(rep.cgImage!, in: CGRect(x: originX, y: originY, width: drawSide, height: drawSide))

// 3. 半径渐隐的 alpha 遮罩：中段完全保留，最外 4px 渐隐，去掉边缘的 JPEG 白边
//    drawsAfterEndLocation 必须开，否则半径之外不绘制，destinationIn 会把外侧留成不透明
let maskRadius = artTarget / 2
let colors = [
    NSColor(white: 1, alpha: 1).cgColor,
    NSColor(white: 1, alpha: 1).cgColor,
    NSColor(white: 1, alpha: 0).cgColor,
] as CFArray
let locations: [CGFloat] = [0, (maskRadius - 4) / maskRadius, 1]
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations)!
ctx.setBlendMode(.destinationIn)
ctx.drawRadialGradient(
    gradient,
    startCenter: CGPoint(x: screenCenter, y: screenCenter), startRadius: 0,
    endCenter: CGPoint(x: screenCenter, y: screenCenter), endRadius: maskRadius,
    options: [.drawsAfterEndLocation]
)
ctx.setBlendMode(.normal)

guard let masked = ctx.makeImage() else {
    print("生成图像失败")
    exit(1)
}

// 4. 再合成一次到全新的预乘透明画布：把 alpha=0 区域残留的白色 RGB 清成 0，
//    否则某些绘制路径会把透明区渲染成白块
guard let cleanCtx = CGContext(
    data: nil,
    width: master,
    height: master,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    print("创建清理上下文失败")
    exit(1)
}
cleanCtx.draw(masked, in: CGRect(x: 0, y: 0, width: master, height: master))
guard let masterImage = cleanCtx.makeImage() else {
    print("生成图像失败")
    exit(1)
}
let bitmap = NSBitmapImageRep(cgImage: masterImage)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    print("编码 PNG 失败")
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outputPath))
print("已输出透明底主图：\(outputPath)（圆盘 \(Int(radius*2))px → \(Int(artTarget))px）")
