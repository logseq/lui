#if os(iOS)
import XCTest
import UIKit
@testable import LUIAppleBackend

@MainActor final class LUIVirtualScrollTopTests: XCTestCase {
    private final class OriginalDelegate: NSObject, UIScrollViewDelegate {
        var allowsReturn = true
        var scrollEvents = 0
        func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool { allowsReturn }
        func scrollViewDidScroll(_ scrollView: UIScrollView) { scrollEvents += 1 }
    }

    func testDistantReturnWaitsForDestinationAndRestoresDelegate() {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        scroll.contentSize = CGSize(width: 320, height: 10_000)
        let original = OriginalDelegate()
        scroll.delegate = original
        let probe = LUIVirtualScrollTopBridge.Probe()
        scroll.addSubview(probe)
        probe.install()
        var requests = 0
        probe.requestTop = { requests += 1 }
        scroll.setContentOffset(CGPoint(x: 0, y: 5000), animated: false)
        XCTAssertEqual(scroll.delegate?.scrollViewShouldScrollToTop?(scroll), false)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(scroll.contentOffset.y, 5000)
        probe.prepared = true
        probe.completeReturn()
        XCTAssertEqual(scroll.contentOffset.y, 0)
        probe.uninstall()
        XCTAssertTrue(scroll.delegate === original)
    }

    func testNearbyReturnAndOriginalDelegateDecisionsArePreserved() {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        scroll.contentSize = CGSize(width: 320, height: 10_000)
        let original = OriginalDelegate()
        scroll.delegate = original
        let probe = LUIVirtualScrollTopBridge.Probe()
        scroll.addSubview(probe)
        probe.install()
        defer { probe.uninstall() }
        var requests = 0
        probe.requestTop = { requests += 1 }
        scroll.setContentOffset(CGPoint(x: 0, y: 50), animated: false)
        XCTAssertEqual(scroll.delegate?.scrollViewShouldScrollToTop?(scroll), true)
        scroll.setContentOffset(CGPoint(x: 0, y: 5000), animated: false)
        original.allowsReturn = false
        XCTAssertEqual(scroll.delegate?.scrollViewShouldScrollToTop?(scroll), false)
        XCTAssertEqual(requests, 0)
        let count = original.scrollEvents
        scroll.delegate?.scrollViewDidScroll?(scroll)
        XCTAssertEqual(original.scrollEvents, count + 1)
    }

    func testNewDragCancelsPendingReturn() {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        scroll.contentSize = CGSize(width: 320, height: 10_000)
        let probe = LUIVirtualScrollTopBridge.Probe()
        scroll.addSubview(probe)
        probe.install()
        defer { probe.uninstall() }
        scroll.setContentOffset(CGPoint(x: 0, y: 5000), animated: false)
        XCTAssertEqual(scroll.delegate?.scrollViewShouldScrollToTop?(scroll), false)
        scroll.delegate?.scrollViewWillBeginDragging?(scroll)
        probe.prepared = true
        probe.completeReturn()
        XCTAssertEqual(scroll.contentOffset.y, 5000)
    }
}
#endif
