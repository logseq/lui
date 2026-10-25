package luimygo

import (
	"encoding/json"
	"testing"

	"github.com/egoist/mygo/ui"
)

func TestCollectionsScrollTokensKeepExactWireIntegers(t *testing.T) {
	for _, kind := range []string{"list", "virtual-list"} {
		t.Run(kind, func(t *testing.T) {
			var events []Event
			b := layoutList(t, kind, 3, &events)
			tt := ui.NewTester(b.View, 400, 300)
			for index, token := range []int64{9007199254740993, 9007199254740992, (1 << 62) - 1} {
				batch := Batch{Generation: int64(index + 2), Ops: []Operation{
					prop(2, "scroll-target", "missing"), prop(2, "scroll-token", token),
				}}
				wire, err := json.Marshal(batch)
				if err != nil {
					t.Fatal(err)
				}
				if err := b.ApplyJSON(wire, false); err != nil {
					t.Fatal(err)
				}
				tt.Frame()
				count := 0
				for _, event := range events {
					if event.Kind == "scroll-completed" && event.Token == token && event.Outcome == "missing-target" {
						count++
					}
				}
				if count != 1 {
					t.Fatalf("wire token %d lost precision or was mistaken for its neighbor: %+v", token, events)
				}
			}
		})
	}
}
