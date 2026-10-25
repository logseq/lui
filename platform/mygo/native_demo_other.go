//go:build (linux || windows) && lui_native_smoke

package luimygo

import "github.com/egoist/mygo/ui"

// NativeDemoBounds exposes committed geometry only to opted-in native tools.
func (b *Backend) NativeDemoBounds(c *ui.Context, id int64) ui.Rect {
	if s := b.states[id]; s != nil {
		return s.handle.Bounds(c)
	}
	return ui.Rect{}
}
