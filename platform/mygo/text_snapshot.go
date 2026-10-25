package luimygo

import "github.com/egoist/mygo/ui"

// InputTextSnapshot reads the actual native TextInput/TextArea's consumed edit
// state, not the model text property or a frame cache. Offsets count runes and
// preserve anchor/caret direction. Call on the UI thread in CaptureInput before
// default handling, or OnChange after input. A window-stable Context is safe for
// this query outside a build. Missing, hidden, disabled, retired, unbound,
// non-input and closed controls report false, not an invented empty selection.
// Custom/raw renderers must BindHostElement to their actual input each build;
// standard text-field/input/textarea controls are already bound.
func (b *Backend) InputTextSnapshot(c *ui.Context, id int64) (text string, anchor, caret int, ok bool) {
	if b.closed || b.probing || c == nil || !b.inputNodeAvailable(id) {
		return
	}
	s := b.states[id]
	if s == nil {
		return
	}
	return s.handle.TextSnapshot(c)
}
