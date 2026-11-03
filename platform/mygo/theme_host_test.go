package luimygo

import (
	"image/color"
	"testing"

	"github.com/egoist/mygo/ui"
)

func TestHostThemeDefaultsAreOwnedAndScoped(t *testing.T) {
	b := New(Config{})
	defer b.Close()
	defaults := map[string]string{"primary": "var(--paint)", "--paint": "rgb(255 0 0)", "--stale": "red"}
	if err := b.SetThemeDefaults(defaults); err != nil {
		t.Fatal(err)
	}
	defaults["--paint"] = "blue"
	apply(t, b, 1, create(1, "root"), create(2, "button"), prop(2, "text", "scoped"), prop(2, "variant", "primary"), prop(2, "theme", `{"primary":"#0000ff"}`), prop(2, "width", 100), prop(2, "height", 40), prop(2, "accessibility-label", "scoped"), insert(1, 2, 0),
		create(3, "button"), prop(3, "text", "host"), prop(3, "variant", "primary"), prop(3, "width", 100), prop(3, "height", 40), prop(3, "accessibility-label", "host"), insert(1, 3, 1))
	tester := ui.NewTester(b.View, 240, 120)
	tester.Move(220, 100)
	layoutWantColor(t, tester, "scoped", .1, .5, layoutBlue)
	layoutWantColor(t, tester, "host", .1, .5, layoutRed)
	if err := b.SetThemeDefaults(map[string]string{"primary": "#00ff00"}); err != nil {
		t.Fatal(err)
	}
	tester.Frame()
	layoutWantColor(t, tester, "host", .1, .5, color.RGBA{G: 255, A: 255})
	ui.NewTester(func(c *ui.Context) {
		if _, err := b.ResolveColor(c, "var(--stale)"); err == nil {
			t.Fatal("replaced host variable survived")
		}
		if _, err := b.ResolveColor(c, "var(--missing, var(--also-missing, #ff0000))"); err != nil {
			t.Fatal(err)
		}
	}, 20, 20)
	if err := b.SetThemeDefaults(nil); err != nil {
		t.Fatal(err)
	}
	tester.Frame()
	accent := ui.LightTheme().Accent
	layoutWantColor(t, tester, "host", .1, .5, color.RGBA{R: accent.R, G: accent.G, B: accent.B, A: 255})
}
