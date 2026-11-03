//go:build darwin && lui_native_smoke

package luimygo

import "github.com/egoist/mygo/ui"

// NativeDemoBounds inspects a retained control in the current committed frame.
// It is available only to explicitly opted-in native qualification commands.
func (b *Backend) NativeDemoBounds(c *ui.Context, id int64) ui.Rect {
	if state := b.states[id]; state != nil {
		return state.handle.Bounds(c)
	}
	return ui.Rect{}
}
