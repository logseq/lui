package luimygo

import (
	"bytes"
	"image"
	"image/color"
	"image/png"
	"math"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/egoist/mygo/ui"
)

type layoutResourceHost interface {
	RegisterImage(int64, image.Image) error
	UnregisterImage(int64)
	PresentMediaSurfaceFrame(int64, image.Image) error
	UnregisterMediaSurface(int64)
}

func layoutResources(t *testing.T, b *Backend) layoutResourceHost {
	t.Helper()
	host, ok := any(b).(layoutResourceHost)
	if !ok {
		t.Fatal("backend lacks the standard image/media resource publication API")
	}
	return host
}

func layoutPixels(left, right color.RGBA) *image.RGBA {
	pixels := image.NewRGBA(image.Rect(0, 0, 4, 2))
	for y := 0; y < 2; y++ {
		for x := 0; x < 4; x++ {
			c := left
			if x >= 2 {
				c = right
			}
			pixels.SetRGBA(x, y, c)
		}
	}
	return pixels
}

var layoutRed = color.RGBA{R: 255, A: 255}
var layoutBlue = color.RGBA{B: 255, A: 255}
var layoutGreen = color.RGBA{G: 255, A: 255}

func layoutColorAt(t *testing.T, tester *ui.Tester, label string, xFraction, yFraction float32) color.RGBA {
	t.Helper()
	rect := layoutRect(t, tester, label)
	x, y := int(rect.X+rect.W*xFraction), int(rect.Y+rect.H*yFraction)
	return tester.Image().RGBAAt(x, y)
}

func layoutSameColor(got, want color.RGBA) bool {
	return math.Abs(float64(got.R)-float64(want.R)) <= 4 && math.Abs(float64(got.G)-float64(want.G)) <= 4 && math.Abs(float64(got.B)-float64(want.B)) <= 4 && got.A >= 250
}

func layoutWantColor(t *testing.T, tester *ui.Tester, label string, x, y float32, want color.RGBA) {
	t.Helper()
	if got := layoutColorAt(t, tester, label, x, y); !layoutSameColor(got, want) {
		t.Fatalf("%s pixel (%g,%g): got %#v, want %#v", label, x, y, got, want)
	}
}

func layoutWait(t *testing.T, tester *ui.Tester, description string, done func() bool) {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		tester.Frame()
		if done() {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatalf("timed out waiting for %s", description)
}

func layoutPNG(t *testing.T, pixels image.Image) []byte {
	t.Helper()
	var encoded bytes.Buffer
	if err := png.Encode(&encoded, pixels); err != nil {
		t.Fatal(err)
	}
	return encoded.Bytes()
}

func TestResourcesRegisteredImageCropReplacementRemovalAndOwnership(t *testing.T) {
	b := New(Config{})
	host := layoutResources(t, b)
	pixels := layoutPixels(layoutRed, layoutBlue)
	if err := host.RegisterImage(7, pixels); err != nil {
		t.Fatal(err)
	}
	apply(t, b, 1, create(1, "root"), prop(1, "cross", "start"), create(2, "image"), prop(2, "image", 7), prop(2, "width", 80), prop(2, "height", 40), prop(2, "accessibility-label", "registered image"), insert(1, 2, 0))
	tester := ui.NewTester(b.View, 300, 200)
	layoutWantColor(t, tester, "registered image", .25, .5, layoutRed)
	layoutWantColor(t, tester, "registered image", .75, .5, layoutBlue)
	// Publication must own its pixels even if the caller immediately reuses its buffer.
	for y := 0; y < 2; y++ {
		for x := 0; x < 4; x++ {
			pixels.SetRGBA(x, y, layoutGreen)
		}
	}
	tester.Frame()
	layoutWantColor(t, tester, "registered image", .25, .5, layoutRed)
	apply(t, b, 2, prop(2, "source-x", 2.0), prop(2, "source-y", 0.0), prop(2, "source-width", 2.0), prop(2, "source-height", 2.0))
	tester.Frame()
	layoutWantColor(t, tester, "registered image", .25, .5, layoutBlue)
	layoutWantColor(t, tester, "registered image", .75, .5, layoutBlue)
	if err := host.RegisterImage(7, layoutPixels(layoutGreen, layoutRed)); err != nil {
		t.Fatal(err)
	}
	tester.Frame()
	layoutWantColor(t, tester, "registered image", .5, .5, layoutRed)
	if err := host.RegisterImage(7, nil); err == nil {
		t.Fatal("nil replacement was accepted")
	}
	tester.Frame()
	layoutWantColor(t, tester, "registered image", .5, .5, layoutRed)
	apply(t, b, 3, Operation{Op: "remove-prop", ID: 2, Property: "source-x"}, Operation{Op: "remove-prop", ID: 2, Property: "source-y"}, Operation{Op: "remove-prop", ID: 2, Property: "source-width"}, Operation{Op: "remove-prop", ID: 2, Property: "source-height"})
	tester.Frame()
	layoutWantColor(t, tester, "registered image", .25, .5, layoutGreen)
	host.UnregisterImage(7)
	tester.Frame()
	if layoutSameColor(layoutColorAt(t, tester, "registered image", .25, .5), layoutGreen) {
		t.Fatal("unregistered image kept showing retired pixels")
	}
	if err := host.RegisterImage(0, pixels); err == nil {
		t.Fatal("accepted zero image ID")
	}
	if err := host.RegisterImage(-1, pixels); err == nil {
		t.Fatal("accepted negative image ID")
	}
}

func TestResourcesMediaFramesReplaceCopyAndRetire(t *testing.T) {
	b := New(Config{})
	host := layoutResources(t, b)
	pixels := layoutPixels(layoutBlue, layoutBlue)
	if err := host.PresentMediaSurfaceFrame(9, pixels); err != nil {
		t.Fatal(err)
	}
	apply(t, b, 1, create(1, "root"), prop(1, "cross", "start"), create(2, "media-surface"), prop(2, "surface", 9), prop(2, "width", 80), prop(2, "height", 40), prop(2, "accessibility-label", "video frame"), insert(1, 2, 0))
	tester := ui.NewTester(b.View, 300, 200)
	layoutWantColor(t, tester, "video frame", .5, .5, layoutBlue)
	for y := 0; y < 2; y++ {
		for x := 0; x < 4; x++ {
			pixels.SetRGBA(x, y, layoutRed)
		}
	}
	tester.Frame()
	layoutWantColor(t, tester, "video frame", .5, .5, layoutBlue)
	if err := host.PresentMediaSurfaceFrame(9, layoutPixels(layoutGreen, layoutGreen)); err != nil {
		t.Fatal(err)
	}
	tester.Frame()
	layoutWantColor(t, tester, "video frame", .5, .5, layoutGreen)
	if err := host.PresentMediaSurfaceFrame(9, nil); err == nil {
		t.Fatal("accepted nil frame")
	}
	if err := host.PresentMediaSurfaceFrame(0, pixels); err == nil {
		t.Fatal("accepted zero surface ID")
	}
	tester.Frame()
	layoutWantColor(t, tester, "video frame", .5, .5, layoutGreen)
	host.UnregisterMediaSurface(9)
	tester.Frame()
	if layoutSameColor(layoutColorAt(t, tester, "video frame", .5, .5), layoutGreen) {
		t.Fatal("retired surface still renders old frame")
	}
	apply(t, b, 2, Operation{Op: "detach-subtree", ID: 2})
	tester.Frame()
	if err := host.PresentMediaSurfaceFrame(9, layoutPixels(layoutRed, layoutRed)); err != nil {
		t.Fatal(err)
	}
	tester.Frame()
	if _, ok := tester.Find("video frame"); ok {
		t.Fatal("publication revived detached surface")
	}
}

func TestResourcesAvatarUsesRegisteredImageCropAndReturnsToFallback(t *testing.T) {
	b := New(Config{})
	host := layoutResources(t, b)
	if err := host.RegisterImage(12, layoutPixels(layoutRed, layoutBlue)); err != nil {
		t.Fatal(err)
	}
	apply(t, b, 1, create(1, "root"), prop(1, "cross", "start"), create(2, "avatar"), prop(2, "text", "AB"), prop(2, "image", 12), prop(2, "width", 40), prop(2, "height", 40), prop(2, "accessibility-label", "person avatar"), prop(2, "source-x", 2.0), prop(2, "source-y", 0.0), prop(2, "source-width", 2.0), prop(2, "source-height", 2.0), insert(1, 2, 0))
	tester := ui.NewTester(b.View, 300, 200)
	layoutWantColor(t, tester, "person avatar", .5, .5, layoutBlue)
	host.UnregisterImage(12)
	tester.Frame()
	if !tester.HasText("AB") {
		t.Fatal("missing resource did not restore avatar initials")
	}
	if layoutSameColor(layoutColorAt(t, tester, "person avatar", .25, .5), layoutBlue) {
		t.Fatal("avatar retained stale image after unregister")
	}
}

func TestResourcesBuiltInIconActuallyDrawsAndUpdates(t *testing.T) {
	b := layoutBackend(t, "icon", nil, prop(2, "name", "check"), prop(2, "width", 64), prop(2, "height", 64), prop(2, "foreground", "#ff00ff"), prop(2, "accessibility-label", "built-in icon"))
	tester := ui.NewTester(b.View, 200, 120)
	countMagenta := func() int {
		bounds := layoutRect(t, tester, "built-in icon")
		count := 0
		for y := int(bounds.Y); y < int(bounds.Y+bounds.H); y++ {
			for x := int(bounds.X); x < int(bounds.X+bounds.W); x++ {
				c := tester.Image().RGBAAt(x, y)
				if c.R > 180 && c.B > 180 && c.G < 80 {
					count++
				}
			}
		}
		return count
	}
	if countMagenta() < 20 {
		t.Fatal("built-in icon produced no colored SVG pixels")
	}
	before := append([]byte(nil), tester.Image().Pix...)
	apply(t, b, 2, prop(2, "name", "arrow-right"))
	tester.Frame()
	if bytes.Equal(before, tester.Image().Pix) {
		t.Fatal("icon name update did not replace glyph")
	}
	apply(t, b, 3, Operation{Op: "remove-prop", ID: 2, Property: "foreground"})
	tester.Frame()
	if countMagenta() != 0 {
		t.Fatal("removed foreground left stale SVG color")
	}
}

func TestResourcesFileImageDecodesFitsAndDropsStalePath(t *testing.T) {
	path := filepath.Join(t.TempDir(), "wide.png")
	if err := os.WriteFile(path, layoutPNG(t, layoutPixels(layoutRed, layoutBlue)), 0600); err != nil {
		t.Fatal(err)
	}
	b := layoutBackend(t, "file-image", nil, prop(2, "path", path), prop(2, "width", 80), prop(2, "height", 80), prop(2, "image-fit", "fit"), prop(2, "background", "#00ff00"), prop(2, "accessibility-label", "local image"))
	tester := ui.NewTester(b.View, 200, 150)
	layoutWait(t, tester, "file decode", func() bool { return layoutSameColor(layoutColorAt(t, tester, "local image", .25, .5), layoutRed) })
	layoutWantColor(t, tester, "local image", .75, .5, layoutBlue)
	layoutWantColor(t, tester, "local image", .5, .1, layoutGreen)
	apply(t, b, 2, prop(2, "image-fit", "fill"))
	tester.Frame()
	if layoutSameColor(layoutColorAt(t, tester, "local image", .5, .1), layoutGreen) {
		t.Fatal("fill mode retained letterboxing")
	}
	apply(t, b, 3, prop(2, "path", filepath.Join(t.TempDir(), "missing.png")))
	tester.Frame()
	layoutWantColor(t, tester, "local image", .25, .5, layoutGreen)
	apply(t, b, 4, Operation{Op: "detach-subtree", ID: 2})
	tester.Frame()
	if _, ok := tester.Find("local image"); ok {
		t.Fatal("detached file image remained visible")
	}
}

func TestResourcesImageURLDiscardsStaleLoadAndEmitsCurrentLoadOnce(t *testing.T) {
	oldStarted, releaseOld := make(chan struct{}), make(chan struct{})
	var release, start sync.Once
	redPNG, bluePNG := layoutPNG(t, layoutPixels(layoutRed, layoutRed)), layoutPNG(t, layoutPixels(layoutBlue, layoutBlue))
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "image/png")
		if r.URL.Path == "/old.png" {
			start.Do(func() { close(oldStarted) })
			<-releaseOld
			_, _ = w.Write(redPNG)
		} else {
			_, _ = w.Write(bluePNG)
		}
	}))
	defer server.Close()
	defer release.Do(func() { close(releaseOld) })
	var events []Event
	b := layoutBackend(t, "image", &events, prop(2, "url", server.URL+"/old.png"), prop(2, "width", 80), prop(2, "height", 40), prop(2, "accessibility-label", "remote image"))
	tester := ui.NewTester(b.View, 200, 150)
	layoutWait(t, tester, "old URI request", func() bool {
		select {
		case <-oldStarted:
			return true
		default:
			return false
		}
	})
	apply(t, b, 2, prop(2, "url", server.URL+"/new.png"))
	tester.Frame()
	layoutWait(t, tester, "replacement URI decode", func() bool { return layoutSameColor(layoutColorAt(t, tester, "remote image", .5, .5), layoutBlue) })
	release.Do(func() { close(releaseOld) })
	for i := 0; i < 10; i++ {
		tester.Frame()
	}
	layoutWantColor(t, tester, "remote image", .5, .5, layoutBlue)
	if len(layoutEvents(events, "load", 2)) != 1 {
		t.Fatalf("stale or repeated load event: %+v", events)
	}
	apply(t, b, 3, Operation{Op: "detach-subtree", ID: 2})
	tester.Frame()
	if _, ok := tester.Find("remote image"); ok {
		t.Fatal("disposed URI completion revived image")
	}
}
