package luimygo

import (
	"fmt"
	"testing"
	"time"

	"github.com/egoist/mygo/ui"
)

func layoutList(t *testing.T, kind string, count int, events *[]Event) *Backend {
	t.Helper()
	ops := []Operation{prop(2, "width", 240), prop(2, "height", 100), prop(2, "gap", 0), prop(2, "pointer-enabled", true), prop(2, "track-visible-range", true)}
	if kind == "virtual-list" {
		ops = append(ops, prop(2, "data-attrs", "data-overscan\x1f2\x1edata-item-extent\x1f20"))
	}
	for i := 0; i < count; i++ {
		id := int64(i + 3)
		ops = append(ops, create(id, "list-item"), prop(id, "key", fmt.Sprintf("row-%d", i)), prop(id, "text", fmt.Sprintf("Row %d", i)), prop(id, "height", 20), prop(id, "appear-enabled", true), insert(2, id, i))
	}
	return layoutBackend(t, kind, events, ops...)
}

func layoutRange(t *testing.T, events []Event, node int64) (int, int) {
	t.Helper()
	ranges := layoutEvents(events, "visible-range", node)
	if len(ranges) == 0 {
		t.Fatalf("no visible range for viewport: %+v", events)
	}
	payload := layoutEventMap(t, ranges[len(ranges)-1])
	first, firstOK := payload["first"].(float64)
	last, lastOK := payload["last"].(float64)
	if !firstOK || !lastOK {
		t.Fatalf("visible-range requires inclusive first/last, including zero: %v", payload)
	}
	return int(first), int(last)
}

func layoutCompletion(t *testing.T, events []Event, token int, outcome string) {
	t.Helper()
	var matches []map[string]any
	for _, e := range layoutEvents(events, "scroll-completed", 2) {
		payload := layoutEventMap(t, e)
		if payload["token"] == float64(token) {
			matches = append(matches, payload)
		}
	}
	if len(matches) != 1 || matches[0]["outcome"] != outcome {
		t.Fatalf("token %d completion must occur exactly once with %q, got %v", token, outcome, matches)
	}
}

func TestCollectionsVirtualListBuildsOnlyViewportAndReportsTrueRange(t *testing.T) {
	var events []Event
	b := layoutList(t, "virtual-list", 10000, &events)
	tester := ui.NewTester(b.View, 400, 300)
	if !tester.HasText("Row 0") || tester.HasText("Row 9999") {
		t.Fatalf("incorrect initial viewport: %v", tester.Texts())
	}
	appearances := 0
	for _, e := range events {
		if e.Kind == "appear" {
			appearances++
		}
	}
	if appearances == 0 || appearances > 32 || len(tester.Texts()) > 64 {
		t.Fatalf("virtualization built work proportional to collection: appearances=%d rendered=%d", appearances, len(tester.Texts()))
	}
	first, last := layoutRange(t, events, 2)
	if first != 0 || last != 4 {
		t.Fatalf("100px viewport of 20px rows must exclude overscan: %d..%d", first, last)
	}
	apply(t, b, 2, prop(2, "scroll-target", "row-9999"), prop(2, "scroll-anchor", "bottom"), prop(2, "scroll-token", 11))
	tester.Frame()
	first, last = layoutRange(t, events, 2)
	if first != 9995 || last != 9999 {
		t.Fatalf("distant scroll did not land at bottom: %d..%d", first, last)
	}
	if !tester.HasText("Row 9999") {
		t.Fatal("target was not built")
	}
	if len(tester.Texts()) > 64 {
		t.Fatal("distant scroll constructed entire intervening collection")
	}
	layoutCompletion(t, events, 11, "succeeded")
	for i := 0; i < 3; i++ {
		tester.Frame()
	}
	layoutCompletion(t, events, 11, "succeeded")
}

func TestCollectionsVisibleRangesForEmptySingleAndVariableRows(t *testing.T) {
	for _, count := range []int{0, 1, 8} {
		t.Run(fmt.Sprint(count), func(t *testing.T) {
			var events []Event
			b := layoutList(t, "virtual-list", count, &events)
			if count == 8 {
				apply(t, b, 2, prop(3, "height", 30), prop(4, "height", 40), prop(5, "height", 50))
			}
			tester := ui.NewTester(b.View, 400, 300)
			first, last := layoutRange(t, events, 2)
			wantLast := map[int]int{0: -1, 1: 0, 8: 2}[count]
			if first != 0 || last != wantLast {
				t.Fatalf("range used estimate/overscan instead of measured viewport: %d..%d, want 0..%d", first, last, wantLast)
			}
			if count > 0 {
				layoutRect(t, tester, "Row 0")
			}
		})
	}
}

func TestCollectionsScrollTargetsMissingRemovedAndTokenReuse(t *testing.T) {
	for _, kind := range []string{"list", "virtual-list"} {
		t.Run(kind, func(t *testing.T) {
			var events []Event
			b := layoutList(t, kind, 50, &events)
			tester := ui.NewTester(b.View, 400, 300)
			apply(t, b, 2, prop(2, "scroll-target", "not-present"), prop(2, "scroll-token", 21))
			tester.Frame()
			layoutCompletion(t, events, 21, "missing-target")
			apply(t, b, 3, prop(2, "scroll-target", "row-30"), prop(2, "scroll-anchor", "top"), prop(2, "scroll-token", 22))
			tester.Frame()
			layoutCompletion(t, events, 22, "succeeded")
			first, _ := layoutRange(t, events, 2)
			if first != 30 {
				t.Fatalf("target did not align to top: %d", first)
			}
			apply(t, b, 4, prop(2, "scroll-target", "row-0"))
			tester.Frame()
			first, _ = layoutRange(t, events, 2)
			if first != 30 {
				t.Fatalf("unchanged request token reissued intent: %d", first)
			}
			apply(t, b, 5, prop(2, "scroll-token", 23), prop(2, "scroll-target", "row-40"), Operation{Op: "detach-subtree", ID: 43})
			tester.Frame()
			layoutCompletion(t, events, 23, "missing-target")
		})
	}
}

func TestCollectionsAnimatedScrollSupersedesAndSettlesExactlyOnce(t *testing.T) {
	var events []Event
	b := layoutList(t, "virtual-list", 10000, &events)
	tester := ui.NewTester(b.View, 400, 300)
	clock, ok := any(tester).(interface{ Advance(time.Duration) })
	if !ok {
		t.Fatal("animated scroll acceptance requires the qualified MyGo deterministic Tester clock")
	}
	apply(t, b, 2, prop(2, "scroll-target", "row-9999"), prop(2, "scroll-token", 31), prop(2, "scroll-animated", true))
	tester.Frame()
	for _, e := range layoutEvents(events, "scroll-completed", 2) {
		if layoutEventMap(t, e)["token"] == float64(31) {
			t.Fatal("animated request completed before a settled frame")
		}
	}
	apply(t, b, 3, prop(2, "scroll-target", "row-100"), prop(2, "scroll-token", 32), prop(2, "scroll-animated", false))
	tester.Frame()
	layoutCompletion(t, events, 31, "cancelled")
	layoutCompletion(t, events, 32, "succeeded")
	clock.Advance(2 * time.Second)
	tester.Frame()
	layoutCompletion(t, events, 31, "cancelled")
	layoutCompletion(t, events, 32, "succeeded")
}

func TestCollectionsVirtualReorderPreservesEditorFocusAndCaret(t *testing.T) {
	var events []Event
	b := layoutList(t, "virtual-list", 100, &events)
	apply(t, b, 2, Operation{Op: "detach-subtree", ID: 3}, create(200, "list-item"), prop(200, "key", "editable"), prop(200, "height", 20),
		create(201, "text-field"), prop(201, "placeholder", "retained row editor"), prop(201, "text", "abcd"), insert(200, 201, 0), insert(2, 200, 0))
	tester := ui.NewTester(b.View, 400, 300)
	if err := tester.Click("retained row editor"); err != nil {
		t.Fatal(err)
	}
	tester.Key(0, ui.KeyHome)
	tester.Key(0, ui.KeyRight)
	apply(t, b, 3, Operation{Op: "move-child", Parent: 2, Child: 200, Index: 2})
	tester.Frame()
	if !tester.Focused("retained row editor") {
		t.Fatal("reordering virtual row lost retained editor identity")
	}
	tester.Type("X")
	changes := layoutEvents(events, "text-changed", 201)
	if len(changes) == 0 || changes[len(changes)-1].Text != "aXbcd" {
		t.Fatalf("caret moved to another retained row: %+v", changes)
	}
}

func TestCollectionsVisibleRangeSubscriptionRemovalAndDispose(t *testing.T) {
	var events []Event
	b := layoutList(t, "virtual-list", 100, &events)
	tester := ui.NewTester(b.View, 400, 300)
	layoutRange(t, events, 2)
	apply(t, b, 2, prop(2, "track-visible-range", false))
	tester.Frame()
	before := len(layoutEvents(events, "visible-range", 2))
	tester.Scroll(100, 50, 0, -80)
	if len(layoutEvents(events, "visible-range", 2)) != before {
		t.Fatal("unsubscribed visible range still emitted")
	}
	apply(t, b, 3, Operation{Op: "detach-subtree", ID: 2})
	tester.Frame()
	count := len(events)
	tester.Scroll(100, 50, 0, -80)
	tester.Frame()
	if len(events) != count {
		t.Fatalf("disposed virtual list emitted stale events: %+v", events[count:])
	}
}

func TestCollectionsTableSharesColumnTracksAndPreservesCells(t *testing.T) {
	var events []Event
	b := layoutBackend(t, "table", &events, prop(2, "width", 400), prop(2, "gap", 0),
		create(3, "table-row"), insert(2, 3, 0),
		create(4, "table-cell"), prop(4, "text", "Name"), prop(4, "font-weight", 700), insert(3, 4, 0),
		create(5, "table-cell"), prop(5, "text", "Status"), prop(5, "font-weight", 700), insert(3, 5, 1),
		create(6, "table-row"), insert(2, 6, 1),
		create(7, "table-cell"), prop(7, "text", "A substantially longer name"), insert(6, 7, 0),
		create(8, "table-cell"), prop(8, "text", "Ready"), prop(8, "press-enabled", true), insert(6, 8, 1))
	tester := ui.NewTester(b.View, 600, 300)
	header, row := layoutRect(t, tester, "Status"), layoutRect(t, tester, "Ready")
	layoutNear(t, "header and data share second-column origin", row.X, header.X)
	if row.Y <= header.Y {
		t.Fatal("table rows overlap")
	}
	if err := tester.Click("Ready"); err != nil {
		t.Fatal(err)
	}
	if len(layoutEvents(events, "press", 8)) != 1 {
		t.Fatal("retained table cell handler was lost")
	}
	apply(t, b, 2, prop(7, "text", "Short"), Operation{Op: "move-child", Parent: 2, Child: 6, Index: 0})
	tester.Frame()
	layoutNear(t, "column origins survive row reorder", layoutRect(t, tester, "Ready").X, layoutRect(t, tester, "Status").X)
	apply(t, b, 3, Operation{Op: "detach-subtree", ID: 6})
	tester.Frame()
	if tester.HasText("Ready") {
		t.Fatal("removed row remained rendered")
	}
	layoutRect(t, tester, "Status")
}

// Extension content instruments real retained row construction without replacing
// any standard renderer. Its rendered text also verifies nested row content.
func TestCollectionsVirtualListHonorsLegacyOverscanAndBoundsActualBuildWork(t *testing.T) {
	for _, overscan := range []int{0, 8} {
		t.Run(fmt.Sprint(overscan), func(t *testing.T) {
			built := make(map[int64]bool)
			b := New(Config{Extensions: map[string]Extension{
				"tests.row-content": {Fingerprint: "v1", Render: func(c *ui.Context, node Node, _ func(), _ func(Event)) {
					built[node.ID] = true
					ui.Text(c, fmt.Sprintf("probe %d", node.ID)).Height(20)
				}},
			}})
			ops := []Operation{create(1, "root"), create(2, "virtual-list"), prop(2, "width", 240), prop(2, "height", 100), prop(2, "gap", 0),
				prop(2, "data-attrs", fmt.Sprintf("data-overscan\x1f%d\x1edata-item-extent\x1f20", overscan)), insert(1, 2, 0)}
			for i := 0; i < 10000; i++ {
				row, content := int64(i+3), int64(i+10003)
				ops = append(ops, create(row, "list-item"), prop(row, "key", fmt.Sprintf("row-%d", i)), prop(row, "height", 20),
					Operation{Op: "create-extension", ID: content, Identifier: "tests.row-content", Fingerprint: "v1"}, insert(row, content, 0), insert(2, row, i))
			}
			apply(t, b, 1, ops...)
			tester := ui.NewTester(b.View, 400, 300)
			if !tester.HasText("probe 10003") {
				t.Fatal("virtual rows lost retained extension children")
			}
			if len(built) < 5 || len(built) > 5+overscan {
				t.Fatalf("overscan=%d built %d distinct rows for five-row viewport", overscan, len(built))
			}
			if overscan > 0 && len(built) < 5+overscan {
				t.Fatalf("requested overscan was ignored: built %d rows", len(built))
			}
			apply(t, b, 2, prop(2, "scroll-target", "row-9999"), prop(2, "scroll-token", 1))
			tester.Frame()
			if !tester.HasText("probe 20002") {
				t.Fatal("distant nested row content was not constructed")
			}
			if len(built) > 2*(5+overscan) {
				t.Fatalf("distant scroll built intervening rows: %d", len(built))
			}
		})
	}
}
