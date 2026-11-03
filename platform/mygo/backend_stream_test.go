package luimygo

import (
	"reflect"
	"strings"
	"testing"

	"github.com/egoist/mygo/ui"
)

func streamStagedApply(b *Backend, source string, snapshot bool) error {
	batch, err := DecodeBatch([]byte(source))
	if err != nil {
		return err
	}
	if snapshot {
		return b.ApplySnapshot(batch)
	}
	return b.ApplyBatch(batch)
}

func streamInitialBackend(t *testing.T) *Backend {
	t.Helper()
	b := mounted(t, nil)
	apply(t, b, 2, create(3, "list-item"), prop(3, "text", "Header"), prop(3, "selected", false), prop(3, "expanded", false), prop(3, "toggle-enabled", true), insert(2, 3, 0), create(4, "text-field"), prop(4, "text", "Original"), prop(4, "placeholder", "Editor"), insert(2, 4, 1), create(5, "slider"), prop(5, "accessibility-label", "Level"), prop(5, "value", 3.0), insert(2, 5, 2))
	ui.NewTester(b.View, 320, 240)
	return b
}

func TestBackendStreamMatchesStagedTransactions(t *testing.T) {
	for _, tc := range []struct {
		name, source string
		snapshot     bool
	}{
		{"last ops rolls back prior mutation", `{"generation":3,"ops":[{"op":"set-prop","id":4,"property":"text","value":"Discarded"}],"ops":[]}`, false},
		{"last ops cannot see earlier creation", `{"generation":3,"ops":[{"op":"create-node","id":6,"kind":"text"}],"ops":[{"op":"set-prop","id":6,"property":"text","value":"Absent"}]}`, false},
		{"last ops replaces earlier semantic error", `{"generation":3,"ops":[{"op":"set-prop","id":999,"property":"text","value":"Discarded"}],"ops":[{"op":"set-prop","id":4,"property":"text","value":"Accepted"}]}`, false},
		{"last ops replaces earlier final contract error", `{"generation":3,"ops":[{"op":"create-node","id":6,"kind":"button"}],"ops":[]}`, false},
		{"null ops is replaced", `{"generation":3,"ops":null,"OPS":[{"op":"set-prop","id":4,"property":"text","value":"Accepted"}]}`, false},
		{"final null ops rolls back", `{"generation":3,"ops":[{"op":"detach-subtree","id":2}],"ops":null}`, false},
		{"earlier structural error remains fatal", `{"generation":3,"ops":[{"op":"invented","id":1}],"ops":[]}`, false},
		{"earlier null required field remains fatal", `{"generation":3,"ops":[{"op":"drop-node","id":null}],"ops":[]}`, false},
		{"earlier malformed unused field remains fatal", `{"generation":3,"ops":[{"op":"drop-node","id":6,"index":false}],"ops":[]}`, false},
		{"last ops retains original incarnation", `{"generation":3,"ops":[{"op":"detach-subtree","id":4},{"op":"create-node","id":4,"kind":"text"}],"ops":[{"op":"set-prop","id":4,"property":"text","value":"Accepted"}]}`, false},
		{"generation follows ops", `{"ops":[{"op":"set-prop","id":4,"property":"text","value":"Accepted"}],"generation":3}`, false},
		{"generation rejection precedes semantic error", `{"ops":[{"op":"set-prop","id":999,"property":"text","value":"Invalid"}],"generation":4}`, false},
		{"generation overwritten after ops", `{"generation":4,"ops":[{"op":"set-prop","id":4,"property":"text","value":"Accepted"}],"Generation":3}`, false},
		{"malformed generation remains fatal", `{"generation":"bad","ops":[],"generation":3}`, false},
		{"trailing document restores deleted subtree", `{"generation":3,"ops":[{"op":"detach-subtree","id":2}]} {}`, false},
		{"truncated document restores mutation", `{"generation":3,"ops":[{"op":"set-prop","id":4,"property":"text","value":"Discarded"}]`, false},
		{"final contract restores retained node", `{"generation":3,"ops":[{"op":"set-prop","id":4,"property":"text","value":"Discarded"},{"op":"create-node","id":6,"kind":"button"}]}`, false},
		{"selected then expanded state order", `{"generation":3,"ops":[{"op":"set-prop","id":3,"property":"selected","value":true},{"op":"set-prop","id":3,"property":"expanded","value":false}]}`, false},
		{"expanded then selected state order", `{"generation":3,"ops":[{"op":"set-prop","id":3,"property":"expanded","value":false},{"op":"set-prop","id":3,"property":"selected","value":true}]}`, false},
		{"all state fields use final values", `{"generation":3,"ops":[{"op":"set-prop","id":4,"property":"text","value":"First"},{"op":"set-prop","id":5,"property":"value","value":4},{"op":"set-prop","id":4,"property":"text","value":"Final"},{"op":"set-prop","id":5,"property":"value","value":6}]}`, false},
		{"state refresh preserves extra operation fields", `{"generation":3,"ops":[{"op":"create-node","id":6,"kind":"text"},{"op":"set-prop","id":3,"property":"expanded","value":true},{"op":"insert-child","parent":2,"child":6,"index":3,"id":3,"property":"selected"}]}`, false},
		{"removed text clears controlled state", `{"generation":3,"ops":[{"op":"set-prop","id":4,"property":"text","value":"Discarded"},{"op":"remove-prop","id":4,"property":"text"}]}`, false},
		{"snapshot replaces earlier candidate", `{"ops":[{"op":"create-node","id":6,"kind":"text"}],"ops":[{"op":"create-node","id":7,"kind":"text"},{"op":"set-prop","id":7,"property":"text","value":"Final"}],"generation":17}`, true},
		{"snapshot failure restores original tree", `{"generation":17,"ops":[{"op":"create-node","id":6,"kind":"text"}],"ops":[{"op":"create-node","id":7,"kind":"button"}]}`, true},
		{"empty snapshot clears original tree", `{"generation":17,"ops":[]}`, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			staged, streamed := streamInitialBackend(t), streamInitialBackend(t)
			defer staged.Close()
			defer streamed.Close()
			wantErr := streamStagedApply(staged, tc.source, tc.snapshot)
			gotErr := streamed.ApplyJSON([]byte(tc.source), tc.snapshot)
			if (wantErr == nil) != (gotErr == nil) || wantErr != nil && wantErr.Error() != gotErr.Error() {
				t.Fatalf("stream error=%v; staged error=%v", gotErr, wantErr)
			}
			if staged.Generation() != streamed.Generation() || !reflect.DeepEqual(staged.Roots(), streamed.Roots()) {
				t.Fatal("generation/root transaction semantics changed")
			}
			switch tc.name {
			case "selected then expanded state order", "state refresh preserves extra operation fields":
				if streamed.states[3].checked {
					t.Fatal("the last checked-state property must resolve to false")
				}
			case "expanded then selected state order":
				if !streamed.states[3].checked {
					t.Fatal("the last selected property must resolve to true")
				}
			case "all state fields use final values":
				if streamed.states[4].text != "Final" || streamed.states[5].value != 6 {
					t.Fatal("controlled state did not use final retained property values")
				}
			case "removed text clears controlled state":
				if streamed.states[4].text != "" {
					t.Fatal("removing text did not reset controlled native state")
				}
			}
			for _, id := range []int64{1, 2, 3, 4, 5, 6, 7} {
				want, exists := staged.Node(id)
				got, gotExists := streamed.Node(id)
				if exists != gotExists || !reflect.DeepEqual(got, want) {
					t.Fatalf("node %d differs: %+v vs %+v", id, got, want)
				}
				wantState, gotState := staged.states[id], streamed.states[id]
				if (wantState == nil) != (gotState == nil) {
					t.Fatalf("state lifetime differs for node %d", id)
				}
				if wantState != nil && (wantState.identity != gotState.identity || wantState.text != gotState.text || wantState.checked != gotState.checked || wantState.value != gotState.value) {
					t.Fatalf("controlled state differs for node %d: text %q/%q checked %v/%v value %v/%v", id, gotState.text, wantState.text, gotState.checked, wantState.checked, gotState.value, wantState.value)
				}
			}
		})
	}
}

func TestBackendStreamRetiresServicesOnlyForCommittedCandidate(t *testing.T) {
	service := &widgetFileService{calls: make(chan widgetFileCall, 4)}
	var events []Event
	b := widgetFileBackend(t, service, &events)
	defer b.Close()
	apply(t, b, 2, create(3, "file-picker"), prop(3, "request", "original"), insert(2, 3, 0))
	tt := ui.NewTester(b.View, 320, 180)
	old := widgetFileNext(t, tt, service)
	original := b.states[3]
	for _, source := range []string{
		`{"generation":3,"ops":[{"op":"detach-subtree","id":3}],"ops":[]}`,
		`{"generation":3,"ops":[{"op":"detach-subtree","id":3}]} trailing`,
		`{"generation":3,"ops":[{"op":"detach-subtree","id":3},{"op":"create-node","id":6,"kind":"button"}]}`,
	} {
		err := b.ApplyJSON([]byte(source), false)
		if strings.Contains(source, `"ops":[]`) {
			if err != nil {
				t.Fatal(err)
			}
		} else if err == nil {
			t.Fatal("invalid retirement committed")
		}
		if old.ctx.Err() != nil || b.states[3] != original {
			t.Fatal("discarded candidate retired an existing service or incarnation")
		}
	}
	source := `{"generation":4,"ops":[{"op":"detach-subtree","id":3}],"ops":[{"op":"detach-subtree","id":3},{"op":"create-node","id":3,"kind":"file-picker"},{"op":"set-prop","id":3,"property":"request","value":"replacement"},{"op":"insert-child","parent":2,"child":3,"index":0}]}`
	if err := b.ApplyJSON([]byte(source), false); err != nil {
		t.Fatal(err)
	}
	if old.ctx.Err() == nil {
		t.Fatal("final committed candidate did not cancel retired service before a frame")
	}
	tt.Frame()
	next := widgetFileNext(t, tt, service)
	old.reply <- widgetFileReply{paths: []string{"/stale/result"}}
	next.reply <- widgetFileReply{}
	widgetFileWait(t, tt, func() bool { return widgetCount(events, "dismiss", 3) == 1 })
	if widgetCount(events, "picked", 3) != 0 {
		t.Fatal("discarded service result reached replacement")
	}
}

func TestBackendStreamClosedBackendNeverReopens(t *testing.T) {
	for _, snapshot := range []bool{false, true} {
		for _, source := range []string{
			`{"generation":2,"ops":[{"op":"create-node","id":2,"kind":"text"}]}`,
			`{"generation":2,"ops":[{"op":"set-prop","id":999,"property":"text","value":"Invalid"}]}`,
			`{"generation":2,"ops":[{"op":"create-node","id":2,"kind":"text"}],"ops":[]}`,
			`{"generation":2,"ops":[{"op":"create-node","id":2,"kind":"text"}]} trailing`,
		} {
			staged, streamed := New(Config{}), New(Config{})
			apply(t, staged, 1, create(1, "column"))
			apply(t, streamed, 1, create(1, "column"))
			staged.Close()
			streamed.Close()
			wantErr := streamStagedApply(staged, source, snapshot)
			gotErr := streamed.ApplyJSON([]byte(source), snapshot)
			if wantErr == nil || gotErr == nil || wantErr.Error() != gotErr.Error() {
				t.Fatalf("closed backend error changed: %v vs %v", gotErr, wantErr)
			}
			if len(streamed.Roots()) != 0 || streamed.Generation() != 1 || len(streamed.states) != 0 {
				t.Fatal("JSON transaction reopened a closed backend")
			}
		}
	}
}
