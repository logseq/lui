#if os(iOS)
import XCTest
import SwiftUI
import UIKit
import LUIAppleBackend

@MainActor
final class LUICheckboxColorTests: XCTestCase {
    func testExplicitForegroundColorsTheCheckedIndicator() throws {
        for checked in [true, false] {
            let backend = LUIAppleBackend()
            try backend.apply(json: """
            {"generation":1,"ops":[
              {"op":"create-node","id":1,"kind":"checkbox"},
              {"op":"set-prop","id":1,"property":"checked","value":\(checked)},
              {"op":"set-prop","id":1,"property":"foreground","value":"#CC2200"}
            ]}
            """)
            let renderer = ImageRenderer(content: LUISwiftUIRoot(backend: backend, rootID: 1)
                .frame(width: 80, height: 60).background(.white))
            let image = try XCTUnwrap(renderer.cgImage)
            var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let counts = pixels.withUnsafeMutableBytes { bytes -> (Int, Int) in
                let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                var red = 0, blue = 0
                for i in stride(from: 0, to: bytes.count, by: 4) {
                    if Int(bytes[i]) > Int(bytes[i + 1]) + 40 { red += 1 }
                    if Int(bytes[i + 2]) > Int(bytes[i]) + 40 { blue += 1 }
                }
                return (red, blue)
            }
            XCTAssertGreaterThan(counts.0, 10)
            XCTAssertEqual(counts.1, 0)
        }
    }
}
#endif
