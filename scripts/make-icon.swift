// Renders the AskNicely app icon (Figma node 6:52: white square, "ask nicely" in SF Pro Display Medium)
// onto a standard 1024x1024 macOS icon canvas, and writes scripts/icon/AppIcon-1024.png.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit
import SwiftUI

let canvas: CGFloat = 1024
let iconBody: CGFloat = 824                 // macOS icon grid: 824pt body inside the 1024 canvas
let inset = (canvas - iconBody) / 2
let s = iconBody / 256                       // Figma frame is 256x256
let radius = iconBody * 0.2237               // macOS icon corner ratio

struct Icon: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.white)
                .frame(width: iconBody, height: iconBody)
                .shadow(color: .black.opacity(0.28), radius: 14, y: 10)
                .offset(x: inset, y: inset)
            Text("ask nicely")
                .font(.system(size: 55.31 * s, weight: .medium))
                .foregroundStyle(.black)
                .fixedSize()
                .offset(x: inset + 10 * s, y: inset + 95 * s)
        }
        .frame(width: canvas, height: canvas, alignment: .topLeading)
    }
}

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fputs("render failed\n", stderr); exit(1)
    }
    try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
