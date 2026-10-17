// Downloads the Discover catalog's icons into BrewDock/DiscoverIcons, so the
// app ships them instead of fetching them each time Discover opens.
//
//   make discover-icons          fetch icons that are missing
//   make discover-icons ALL=1    fetch every icon again
//
// Each icon's source is the icon(...) argument of its entry in
// DiscoverPackage.swift. Entries without one show a symbol tile instead.

import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalog = root.appendingPathComponent("BrewDock/DiscoverPackage.swift")
let outDir = root.appendingPathComponent("BrewDock/DiscoverIcons")
let refetchAll = CommandLine.arguments.contains("--all")
let pixels = 64   // 30pt tiles at 2x, with a little to spare

/// The URL for an icon(...) argument, mirroring icon() and favicon() in the catalog
func url(for argument: String) -> URL? {
    let favicon = try! NSRegularExpression(pattern: #"^favicon\("([^"]+)"\)$"#)
    let plain = try! NSRegularExpression(pattern: #"^"([^"]+)"$"#)
    let range = NSRange(argument.startIndex..., in: argument)
    if let m = favicon.firstMatch(in: argument, range: range), let r = Range(m.range(at: 1), in: argument) {
        return URL(string: "https://www.google.com/s2/favicons?domain=\(argument[r])&sz=128")
    }
    if let m = plain.firstMatch(in: argument, range: range), let r = Range(m.range(at: 1), in: argument) {
        let source = String(argument[r])
        return URL(string: source.contains("://") ? source : "https://icon.horse/icon/\(source)")
    }
    return nil
}

func download(_ url: URL) -> Data? {
    for attempt in 1...4 {
        var result: Data?
        var retry = false
        let done = DispatchSemaphore(value: 0)
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let http = response as? HTTPURLResponse
            if http?.statusCode == 200, http?.mimeType?.hasPrefix("image/") == true {
                result = data
            } else {
                retry = http?.statusCode == 429 || http == nil
            }
            done.signal()
        }.resume()
        done.wait()
        if result != nil || !retry { return result }
        Thread.sleep(forTimeInterval: Double(attempt) * 3)
    }
    return nil
}

/// Draws the image into a square PNG, scaled to fit
func png(from data: Data) -> Data? {
    guard let image = NSImage(data: data), image.size.width > 0 else { return nil }
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let side = CGFloat(pixels)
    let scale = min(side / image.size.width, side / image.size.height)
    let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
    image.draw(in: NSRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let source = try String(contentsOf: catalog, encoding: .utf8)
let entry = try NSRegularExpression(pattern: #"\.init\("([^"]+)",.*,\s*icon\((.+)\)\)"#)
var wanted: [String: URL] = [:]
for line in source.split(separator: "\n") {
    let line = String(line)
    guard let m = entry.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
          let idRange = Range(m.range(at: 1), in: line), let argRange = Range(m.range(at: 2), in: line),
          let url = url(for: String(line[argRange])) else { continue }
    wanted[String(line[idRange])] = url
}

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
var fetched = 0, failed: [String] = []
for (id, url) in wanted.sorted(by: { $0.key < $1.key }) {
    let file = outDir.appendingPathComponent("discover-\(id).png")
    if !refetchAll, FileManager.default.fileExists(atPath: file.path) { continue }
    if let data = download(url), let image = png(from: data) {
        try image.write(to: file)
        fetched += 1
    } else {
        failed.append("\(id) (\(url.absoluteString))")
    }
    Thread.sleep(forTimeInterval: 0.4)   // the icon services rate-limit
}

// Drop icons for entries that were removed or no longer have one
var removed = 0
for file in try FileManager.default.contentsOfDirectory(atPath: outDir.path) where file.hasPrefix("discover-") {
    let id = String(file.dropFirst("discover-".count).dropLast(".png".count))
    if wanted[id] == nil {
        try FileManager.default.removeItem(at: outDir.appendingPathComponent(file))
        removed += 1
    }
}

print("\(wanted.count) icons in the catalog: fetched \(fetched), removed \(removed), failed \(failed.count)")
failed.forEach { print("  failed: \($0)") }
exit(failed.isEmpty ? 0 : 1)
