package luimygo

import (
	"fmt"
	"image"
	"image/color"
	"testing"

	"github.com/egoist/mygo/ui"
)

func TestResearchVirtualList(t *testing.T) {
	var state ui.ListState
	state.Key = func(i int) any { return i }
	built := 0
	tt := ui.NewTester(func(c *ui.Context) {
		ui.List(c, &state, 10000, func(i int) {
			built++
			ui.Text(c, fmt.Sprintf("row-%d", i)).Height(24)
		}).Size(240, 120)
	}, 320, 240)
	first, last := state.Visible()
	t.Logf("initial built=%d visible=%d..%d", built, first, last)
	if built >= 100 || first != 0 || last >= 20 {
		t.Fatal("list did not virtualize")
	}
	state.ScrollTo(9999, ui.End)
	tt.Frame()
	first, last = state.Visible()
	t.Logf("after jump built=%d visible=%d..%d", built, first, last)
	if last != 9999 || first < 9900 {
		t.Fatal("jump did not reach final row")
	}
}

func TestResearchLocalLayers(t *testing.T) {
	var stack, overlay ui.Handle
	var stackBox, overlayBox ui.Rect
	tt := ui.NewTester(func(c *ui.Context) {
		stackBox, overlayBox = stack.Bounds(c), overlay.Bounds(c)
		ui.Column(c).AlignItems(ui.Start).Children(func() {
			ui.Grid(c).ColumnTracks(ui.FitContent()).RowTracks(ui.FitContent()).Bind(&stack).Children(func() {
				ui.Box(c).Size(50, 20).ColumnStart(1).RowStart(1)
				ui.Box(c).Size(80, 90).ColumnStart(1).RowStart(1)
			})
			ui.Box(c).Bind(&overlay).Children(func() {
				ui.Box(c).Size(120, 60)
				ui.Box(c).Size(400, 90).Absolute().Left(0).Top(0)
			})
		})
	}, 640, 480)
	tt.Frame()
	t.Logf("stack=%+v overlay=%+v", stackBox, overlayBox)
	if stackBox.W != 80 || stackBox.H != 90 {
		t.Fatal("stack intrinsic size mismatch")
	}
	if overlayBox.W != 120 || overlayBox.H != 60 {
		t.Fatal("overlay altered base intrinsic size")
	}
}

func TestResearchSourceRegion(t *testing.T) {
	src := image.NewRGBA(image.Rect(0, 0, 4, 2))
	for y := range 2 {
		for x := range 4 {
			c := color.RGBA{R: 255, A: 255}
			if x >= 2 {
				c = color.RGBA{B: 255, A: 255}
			}
			src.SetRGBA(x, y, c)
		}
	}
	bitmap := ui.NewBitmap(src)
	tt := ui.NewTester(func(c *ui.Context) {
		ui.Box(c).Size(20, 20).Draw(func(p *ui.Painter, r ui.Rect) {
			p.ImageRegion(bitmap, ui.Rect{X: 2, Y: 0, W: 2, H: 2}, r, ui.ImageOptions{})
		})
	}, 40, 40)
	r, g, b, a := tt.Image().At(10, 10).RGBA()
	t.Logf("cropped pixel=%d,%d,%d,%d", r, g, b, a)
	if b < 60000 || r > 1000 || g > 1000 {
		t.Fatal("source crop sampled wrong region")
	}
}
