package luimygo

import (
	"github.com/egoist/mygo/ui"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestRuntimeMissingLibrary(t *testing.T) {
	if _, err := OpenRuntime("/definitely/missing/lui-library", New(Config{})); err == nil {
		t.Fatal("opened missing library")
	}
}

// This test uses the actual OCaml reducer, wire encoder and C ABI. The test
// script builds the existing Todos native library and sets LUI_MYGO_TEST_LIBRARY.
func TestOCamlTodosEndToEnd(t *testing.T) {
	path := os.Getenv("LUI_MYGO_TEST_LIBRARY")
	if path == "" {
		t.Skip("run tooling/test_mygo.sh for the OCaml integration test")
	}
	b := New(Config{})
	r, err := OpenRuntime(path, b)
	if err != nil {
		t.Fatal(err)
	}
	defer r.Close()
	if _, err := OpenRuntime(path, New(Config{})); err == nil {
		t.Fatal("opened concurrent OCaml session")
	}
	if err := r.Dispatch(Event{Kind: "unknown-event", Node: 1}); err == nil {
		t.Fatal("unknown event was accepted")
	}
	tester := ui.NewTester(b.View, 800, 600)
	if !tester.HasText("Todos") || !tester.HasText("0 remaining / 0 total") {
		t.Fatal(tester.Texts())
	}
	add := func(title string) {
		t.Helper()
		if err := tester.Click("New todo"); err != nil {
			t.Fatal(err)
		}
		tester.Type(title)
		if err := tester.Click("Add"); err != nil {
			t.Fatal(err)
		}
		if b.Err() != nil {
			t.Fatal(b.Err())
		}
	}
	add("first 你好 🌍")
	if !tester.HasText("[ ] first 你好 🌍") || !tester.HasText("1 remaining / 1 total") {
		t.Fatal(tester.Texts())
	}
	add("second")
	if err := tester.Click("Done"); err != nil {
		t.Fatal(err)
	}
	if !tester.HasText("[x] first 你好 🌍") || !tester.HasText("1 remaining / 2 total") {
		t.Fatal(tester.Texts())
	}
	// Deliberately lose one generation: the next runtime delta must trigger
	// an authoritative resync, preserving the actual OCaml model state.
	apply(t, b, b.Generation()+1)
	if err := tester.Click("Undo"); err != nil {
		t.Fatal(err)
	}
	if !tester.HasText("[ ] first 你好 🌍") {
		t.Fatal("automatic delta recovery failed")
	}
	if err := tester.Click("Done"); err != nil {
		t.Fatal(err)
	}
	before := b.Generation()
	if err := r.Resync(); err != nil {
		t.Fatal(err)
	}
	tester.Frame()
	if b.Generation() != before || !tester.HasText("[x] first 你好 🌍") {
		t.Fatal("snapshot lost app state")
	}
	if err := tester.Click("Delete"); err != nil {
		t.Fatal(err)
	}
	if tester.HasText("first 你好 🌍") || !tester.HasText("1 remaining / 1 total") {
		t.Fatal(tester.Texts())
	}
	if err := r.Close(); err != nil {
		t.Fatal(err)
	}
	if len(b.Roots()) != 0 {
		t.Fatal("stop left live UI nodes")
	}
	if r.Dispatch(Event{Kind: "press", Node: 1}) == nil {
		t.Fatal("dispatch after close succeeded")
	}
	// Restart must reuse the original OCaml domain thread safely.
	r2, err := OpenRuntime(path, b)
	if err != nil {
		t.Fatal(err)
	}
	defer r2.Close()
	tester.Frame()
	if !tester.HasText("0 remaining / 0 total") {
		t.Fatal("restart retained old state")
	}
	for id, node := range b.nodes {
		if node.Kind == "textarea" {
			value := "before\x00after 你好 🌍"
			if err := r2.Dispatch(Event{Kind: "text-changed", Node: id, Text: value}); err != nil {
				t.Fatal(err)
			}
			updated, _ := b.Node(id)
			if updated.String("text") != value {
				t.Fatal("UTF-8 ABI truncated text at embedded NUL")
			}
		}
	}

}

func TestIncompleteRuntimeLibrary(t *testing.T) {
	cc, err := exec.LookPath("cc")
	if err != nil {
		t.Skip("a C compiler is required for the ABI validation test")
	}
	dir := t.TempDir()
	source := filepath.Join(dir, "incomplete.c")
	if err := os.WriteFile(source, []byte("int unrelated(void) { return 1; }\n"), 0600); err != nil {
		t.Fatal(err)
	}
	suffix := ".so"
	if runtime.GOOS == "darwin" {
		suffix = ".dylib"
	}
	if runtime.GOOS == "windows" {
		suffix = ".dll"
	}
	library := filepath.Join(dir, "incomplete"+suffix)
	if output, err := exec.Command(cc, "-shared", "-fPIC", "-o", library, source).CombinedOutput(); err != nil {
		t.Fatalf("compile ABI fixture: %s: %v", output, err)
	}
	w := runtimeWorker{}
	if err := w.load(library); err == nil || !strings.Contains(err.Error(), "missing symbol") {
		t.Fatalf("missing ABI exports must be a regular loader error: %v", err)
	}
	if w.library != 0 {
		t.Fatal("incomplete runtime library was retained")
	}
}
