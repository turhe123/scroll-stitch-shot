import CoreGraphics

/// Downsampled 8-bit grayscale copy of a frame's content rows, used only for overlap matching.
private struct GrayFrame {
    static let columns = 96
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init?(_ image: CGImage, top: Int, bottom: Int) {
        let width = min(Self.columns, image.width)
        let fullHeight = image.height
        guard width > 0, fullHeight - top - bottom > 0,
              let ctx = CGContext(data: nil, width: width, height: fullHeight, bitsPerComponent: 8,
                                  bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let data = ctx.data else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: fullHeight))
        // Bitmap memory row 0 is the visual top of the image.
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * fullHeight)
        let start = top * width
        let count = (fullHeight - top - bottom) * width
        self.pixels = Array(UnsafeBufferPointer(start: buffer + start, count: count))
        self.width = width
        self.height = fullHeight - top - bottom
    }
}

/// Finds the vertical overlap between consecutive frames and assembles the stitched output image(s).
final class Stitcher {
    enum AddResult: Equatable { case added(rows: Int), identical, unusable }

    /// A slice of rows (top-origin pixel coordinates) of a captured frame that becomes part of the output.
    private struct Segment { let image: CGImage; let rows: Range<Int> }

    /// Mean absolute gray difference above which a match is considered poor.
    private let misalignThreshold = 12.0
    private let headerPx: Int
    private let footerPx: Int
    private var segments: [Segment] = []
    private var lastFrame: CGImage?
    private var lastGray: GrayFrame?
    private(set) var frameCount = 0
    private(set) var possiblyMisaligned = false

    init(headerPx: Int, footerPx: Int) {
        self.headerPx = max(0, headerPx)
        self.footerPx = max(0, footerPx)
    }

    private func trims(for height: Int) -> (top: Int, bottom: Int) {
        (min(headerPx, height / 3), min(footerPx, height / 3))
    }

    /// Adds a frame. `expectedShift` (pixels) breaks ties on featureless content in automatic mode.
    func add(_ frame: CGImage, expectedShift: Int?) -> AddResult {
        let (top, bottom) = trims(for: frame.height)
        guard let gray = GrayFrame(frame, top: top, bottom: bottom) else { return .unusable }
        let contentEnd = frame.height - bottom

        guard let prev = lastGray, let prevFrame = lastFrame else {
            segments.append(Segment(image: frame, rows: 0..<contentEnd))
            lastFrame = frame
            lastGray = gray
            frameCount = 1
            return .added(rows: contentEnd)
        }

        var shift: Int
        if prev.height == gray.height, prev.width == gray.width, frame.width == prevFrame.width {
            if Self.meanDifference(prev, gray, shift: 0, bandRows: gray.height, step: 2) < 1.0 { return .identical }
            let match = bestShift(prev, gray, expected: expectedShift)
            shift = match.shift
            if match.score > misalignThreshold { possiblyMisaligned = true }
        } else {
            // Frame size changed (e.g. display change); append the whole content and flag it.
            shift = gray.height
            possiblyMisaligned = true
        }
        shift = max(1, min(shift, contentEnd - top))
        segments.append(Segment(image: frame, rows: (contentEnd - shift)..<contentEnd))
        lastFrame = frame
        lastGray = gray
        frameCount += 1
        return .added(rows: shift)
    }

    /// Searches every candidate offset, comparing the bottom band of `prev` against `next`.
    private func bestShift(_ prev: GrayFrame, _ next: GrayFrame, expected: Int?) -> (shift: Int, score: Double) {
        let h = prev.height
        let band = max(8, h / 5)
        guard h > band + 1 else { return (h, .infinity) }
        var best = (shift: h - band, score: Double.infinity)
        for shift in 1...(h - band) {
            let raw = Self.meanDifference(prev, next, shift: shift, bandRows: band, step: 4, cutoff: best.score)
            let penalty = expected.map { Double(abs(shift - $0)) / Double(h) * 2.0 } ?? 0
            if raw + penalty < best.score { best = (shift, raw + penalty) }
        }
        return best
    }

    /// Mean absolute difference between the last `bandRows` rows of `a` and the same rows of `b` moved up by `shift`.
    private static func meanDifference(_ a: GrayFrame, _ b: GrayFrame, shift: Int, bandRows: Int,
                                       step: Int, cutoff: Double = .infinity) -> Double {
        let w = a.width, h = a.height
        let firstRow = h - bandRows
        var total = 0, samples = 0
        let rowsSampled = (bandRows + step - 1) / step
        let limit = cutoff.isFinite ? Int(cutoff * Double(rowsSampled * w)) : Int.max
        a.pixels.withUnsafeBufferPointer { pa in
            b.pixels.withUnsafeBufferPointer { pb in
                var row = firstRow
                while row < h {
                    let ia = row * w, ib = (row - shift) * w
                    for x in 0..<w { total += abs(Int(pa[ia + x]) - Int(pb[ib + x])) }
                    samples += w
                    if total > limit { return }
                    row += step
                }
            }
        }
        return samples == 0 ? .infinity : Double(total) / Double(samples)
    }

    /// Renders the stitched result, split into pages no taller than `maxHeight` pixels.
    func render(maxHeight: Int = 16_000) -> [CGImage] {
        guard let first = segments.first, let last = lastFrame else { return [] }
        var parts = segments
        let (_, bottom) = trims(for: last.height)
        if bottom > 0 { parts.append(Segment(image: last, rows: (last.height - bottom)..<last.height)) }

        let width = first.image.width
        let total = parts.reduce(0) { $0 + $1.rows.count }
        let space = first.image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        var pages: [CGImage] = []

        for pageTop in stride(from: 0, to: total, by: maxHeight) {
            let pageHeight = min(maxHeight, total - pageTop)
            guard let ctx = CGContext(data: nil, width: width, height: pageHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                        | CGBitmapInfo.byteOrder32Little.rawValue) else { continue }
            var outY = 0
            for part in parts {
                let lo = max(outY, pageTop), hi = min(outY + part.rows.count, pageTop + pageHeight)
                if lo < hi {
                    let srcTop = part.rows.lowerBound + (lo - outY)
                    let crop = CGRect(x: 0, y: srcTop, width: min(width, part.image.width), height: hi - lo)
                    if let slice = part.image.cropping(to: crop) {
                        ctx.draw(slice, in: CGRect(x: 0, y: CGFloat(pageHeight - (hi - pageTop)),
                                                   width: crop.width, height: crop.height))
                    }
                }
                outY += part.rows.count
            }
            if let image = ctx.makeImage() { pages.append(image) }
        }
        return pages
    }
}
