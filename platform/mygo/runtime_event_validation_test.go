package luimygo

import (
	"math"
	"strings"
	"testing"
)

func TestRuntimeRejectsInvalidPayloadBeforeNativeEntry(t *testing.T) {
	closed := &Runtime{closed: true, worker: nativeWorker()}
	cases := []Event{
		{Kind: "press", Node: 0}, {Kind: "press", Node: math.MaxInt64},
		{Kind: "pointer-down", Node: 1, X: math.NaN()},
		{Kind: "pointer-up", Node: 1, Y: math.Inf(1)},
		{Kind: "press-detail", Node: 1, Modifiers: 16},
		{Kind: "context-menu-press", Node: 1, Button: 3},
		{Kind: "pointer-down", Node: 1, TargetClass: string([]byte{0xff})},
		{Kind: "value-changed", Node: 1, Value: math.Inf(-1)},
		{Kind: "text-changed", Node: 1, Text: string([]byte{0xff})},
		{Kind: "scroll-completed", Node: 1, Token: -1, Outcome: "succeeded"},
		{Kind: "scroll-completed", Node: 1, Token: 1, Outcome: "invented"},
		{Kind: "visible-range", Node: 1, First: 3, Last: 2},
		{Kind: "visible-range", Node: 1, First: 1, Last: -1},
		{Kind: "navigation-key", Node: 1, Key: "Delete"},
		{Kind: "unrecognized", Node: 1},
	}
	for _, event := range cases {
		err := closed.Dispatch(event)
		if err == nil || !strings.Contains(err.Error(), "invalid event") {
			t.Errorf("%+v reached session/native entry instead of validation: %v", event, err)
		}
	}
	for _, event := range []Event{
		{Kind: "press", Node: 1}, {Kind: "visible-range", Node: 1, First: 0, Last: -1},
		{Kind: "pointer-down", Node: 1, X: -1.25, Y: 2, Modifiers: 15, Button: 2, TargetClass: "a\x00你好"},
		{Kind: "scroll-completed", Node: 1, Token: 9007199254740993, Outcome: "missing-target"},
	} {
		err := closed.Dispatch(event)
		if err == nil || !strings.Contains(err.Error(), "session is closed") {
			t.Errorf("valid payload rejected before closed-session check: %+v: %v", event, err)
		}
	}
}
