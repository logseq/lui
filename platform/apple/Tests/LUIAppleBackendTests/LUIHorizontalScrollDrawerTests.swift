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
        XCTAssertFalse(LUIDrawerScrollInteractionPolicy.defersToHorizontalScroll(from: cell))
    }
}
#endif
