#if os(iOS)
import UIKit
import XCTest
@testable import LUIAppleBackend

@MainActor final class LUIHorizontalScrollDrawerTests: XCTestCase {
    func testNestedHorizontalScrollHasPriorityOverDrawer() {
        let page = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        page.contentSize = CGSize(width: 320, height: 1200)
        let table = UIScrollView(frame: CGRect(x: 0, y: 100, width: 320, height: 200))
        table.contentSize = CGSize(width: 1200, height: 200)
        let cell = UILabel()
        page.addSubview(table)
        table.addSubview(cell)
        XCTAssertTrue(LUIDrawerScrollInteractionPolicy.defersToHorizontalScroll(from: cell))
        XCTAssertFalse(LUIDrawerScrollInteractionPolicy.defersToHorizontalScroll(from: page))
        table.isScrollEnabled = false
        XCTAssertFalse(LUIDrawerScrollInteractionPolicy.defersToHorizontalScroll(from: cell))
        table.isScrollEnabled = true
        table.contentSize.width = 320
        table.alwaysBounceHorizontal = true
        XCTAssertFalse(LUIDrawerScrollInteractionPolicy.defersToHorizontalScroll(from: cell))
        table.contentInset = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        XCTAssertTrue(LUIDrawerScrollInteractionPolicy.defersToHorizontalScroll(from: cell))
    }
}
#endif
