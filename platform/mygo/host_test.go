package luimygo

import (
	"testing"

	"github.com/egoist/mygo/ui"
)

func TestHostOperationsRespectNodeLifetime(t *testing.T) {
	b := New(Config{})
	apply(t, b, 1, create(1, "root"), create(2, "scroll"), prop(2, "height", 80), insert(1, 2, 0),
		create(3, "input"), prop(3, "text", "source"), insert(2, 3, 0),
		create(4, "box"), prop(4, "height", 500), insert(2, 4, 1))
	if err := b.RequestFocus(3); err != nil {
		t.Fatal(err)
	}
	if err := b.ScrollTo(2, 0, 40); err != nil {
		t.Fatal(err)
	}
	var bounds ui.Rect
	var committed bool
	tester := ui.NewTester(func(c *ui.Context) {
		b.View(c)
		c.AfterFrame(func() { bounds, committed = b.Bounds(c, 2) })
	}, 300, 200)
	tester.Frame()
	tester.Frame()
	if !committed || bounds.H != 80 {
		t.Fatalf("committed viewport: %+v, %v", bounds, committed)
	}
	_, y, err := b.ScrollOffset(2)
	if err != nil || y != 40 {
		t.Fatalf("scroll offset: %v, %v", y, err)
	}
	apply(t, b, 2, Operation{Op: "detach-subtree", ID: 2})
	if err := b.RequestFocus(3); err == nil {
		t.Fatal("accepted focus for dropped node")
	}
	if err := b.ScrollTo(2, 0, 0); err == nil {
		t.Fatal("accepted scroll for dropped node")
	}
	apply(t, b, 3, create(2, "scroll"), insert(1, 2, 0))
	_, y, err = b.ScrollOffset(2)
	if err != nil || y != 0 {
		t.Fatalf("recreated node inherited scroll: %v, %v", y, err)
	}
	b.Close()
	if err := b.RequestFocus(2); err == nil {
		t.Fatal("accepted focus after close")
	}
}
