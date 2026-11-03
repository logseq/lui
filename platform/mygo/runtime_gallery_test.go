package luimygo

import (
	"os"
	"testing"

	"github.com/egoist/mygo/ui"
)

func TestOCamlComponentsDesktopGalleryInteraction(t *testing.T) {
	path := os.Getenv("LUI_MYGO_COMPONENTS_LIBRARY")
	if path == "" {
		t.Skip("run tooling/test_mygo.sh for real Components integration")
	}
	b := New(Config{})
	defer b.Close()
	runtime, err := OpenRuntime(path, b)
	if err != nil {
		t.Fatal(err)
	}
	defer runtime.Close()
	tt := ui.NewTester(b.View, 1000, 760)
	// A desktop window must expose the entire real gallery through scrolling.
	// A giant unconstrained column can render its first section but cannot
	// reveal the actual event controls at the end of the application.
	tt.Scroll(950, 700, 0, 100000)
	r, ok := tt.Find("Event input")
	if !ok || r.Y < 0 || r.Y+r.H > 760 {
		t.Fatalf("desktop gallery cannot scroll to its actual event editor: %+v", r)
	}
	click := func(text string) {
		t.Helper()
		tt.Scroll(950, 700, 0, -100000)
		for attempt := 0; attempt < 80; attempt++ {
			bounds, found := tt.Find(text)
			if !found {
				t.Fatalf("missing actual gallery control %q", text)
			}
			if bounds.Y >= 80 && bounds.H > 0 && bounds.Y+bounds.H < 680 {
				break
			}
			tt.Scroll(950, 700, 0, 320)
		}
		widgetClick(t, tt, text)
		if b.Err() != nil {
			t.Fatal(b.Err())
		}
	}
	click("Toggle disabled")
	if !tt.HasText("Controls are disabled.") {
		for _, node := range b.nodes {
			if node.String("text") == "Controls are disabled." {
				tt.Scroll(950, 700, 0, 100)
				break
			}
		}
		if !tt.HasText("Controls are disabled.") {
			t.Fatalf("actual OCaml disabled reducer did not update the gallery: generation=%d", b.Generation())
		}
	}
	click("Toggle disabled")
	if tt.HasText("Controls are disabled.") {
		t.Fatal("actual conditional removal did not retire disabled feedback")
	}
	click("Open dialog")
	if !tt.HasText("Choose a new name for this note.") {
		t.Fatal("actual retained dialog failed to mount")
	}
	tt.Key(0, ui.KeyEscape)
	if tt.HasText("Choose a new name for this note.") {
		t.Fatal("dialog dismissal did not reach the actual OCaml reducer")
	}
	click("Open sheet")
	if !tt.HasText("Anyone with the link can view this showcase.") {
		t.Fatal("actual retained sheet failed to mount")
	}
	tt.Key(0, ui.KeyEscape)
	if tt.HasText("Anyone with the link can view this showcase.") {
		t.Fatal("sheet dismissal did not remove its retained presentation")
	}
	click("Choose environment")
	tt.Key(0, ui.KeyDown)
	tt.Key(0, ui.KeyEnter)
	if !tt.HasText("Environment: Staging") {
		t.Fatal("actual retained menu selection did not update the model")
	}
	if err := runtime.Resync(); err != nil {
		t.Fatal(err)
	}
	tt.Frame()
	if !tt.HasText("Environment: Staging") || b.Err() != nil {
		t.Fatal("real Gallery state did not survive authoritative resync", b.Err())
	}
}
