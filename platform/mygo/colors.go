package luimygo

import (
	"math"
	"strconv"
	"strings"
	"unicode"

	"github.com/egoist/mygo/ui"
	"golang.org/x/image/colornames"
)

// styleFields keeps a functional color intact while splitting shadow lengths.
func styleFields(value string) []string {
	var fields []string
	start, depth := -1, 0
	for i, r := range value {
		if unicode.IsSpace(r) && depth == 0 {
			if start >= 0 {
				fields = append(fields, value[start:i])
				start = -1
			}
			continue
		}
		if start < 0 {
			start = i
		}
		if r == '(' {
			depth++
		}
		if r == ')' {
			depth--
		}
	}
	if start >= 0 {
		fields = append(fields, value[start:])
	}
	return fields
}

func styleColor(value string) (ui.Color, bool) {
	value = strings.ToLower(strings.TrimSpace(value))
	if validHex(value) {
		return ui.Hex(value), true
	}
	if value == "rebeccapurple" {
		return ui.RGB(102, 51, 153), true
	}
	if c, ok := colornames.Map[value]; ok {
		return ui.RGBA(c.R, c.G, c.B, float32(c.A)/255), true
	}
	name, body, ok := strings.Cut(value, "(")
	if !ok || !strings.HasSuffix(body, ")") {
		return ui.Color{}, false
	}
	components := strings.Fields(strings.NewReplacer(",", " ", "/", " ").Replace(strings.TrimSuffix(body, ")")))
	if len(components) < 3 || len(components) > 4 {
		return ui.Color{}, false
	}
	parse := func(s string, scale float64) (float64, bool) {
		percent := strings.HasSuffix(s, "%")
		if percent {
			s = strings.TrimSuffix(s, "%")
		}
		n, err := strconv.ParseFloat(s, 64)
		if err != nil || math.IsNaN(n) || math.IsInf(n, 0) {
			return 0, false
		}
		if percent {
			n = n * scale / 100
		}
		return n, true
	}
	alpha := float64(1)
	if len(components) == 4 {
		var valid bool
		alpha, valid = parse(components[3], 1)
		if !valid {
			return ui.Color{}, false
		}
	}
	var r, g, b float64
	switch name {
	case "rgb", "rgba":
		var good bool
		r, good = parse(components[0], 255)
		if !good {
			return ui.Color{}, false
		}
		g, good = parse(components[1], 255)
		if !good {
			return ui.Color{}, false
		}
		b, good = parse(components[2], 255)
		if !good {
			return ui.Color{}, false
		}
	case "oklch":
		l, good := parse(components[0], 1)
		if !good {
			return ui.Color{}, false
		}
		chroma, good := parse(components[1], .4)
		if !good {
			return ui.Color{}, false
		}
		hue, good := parse(strings.TrimSuffix(components[2], "deg"), 1)
		if !good {
			return ui.Color{}, false
		}
		return ui.Oklch(float32(l), float32(chroma), float32(hue)).Alpha(float32(max(0, min(1, alpha)))), true
	case "hsl", "hsla":
		hue := components[0]
		factor := float64(1)
		for _, unit := range []struct {
			name   string
			factor float64
		}{{"turn", 360}, {"grad", .9}, {"rad", 180 / math.Pi}, {"deg", 1}} {
			if strings.HasSuffix(hue, unit.name) {
				hue = strings.TrimSuffix(hue, unit.name)
				factor = unit.factor
				break
			}
		}
		h, good := parse(hue, 1)
		if !good {
			return ui.Color{}, false
		}
		sat, good := parse(components[1], 1)
		if !good {
			return ui.Color{}, false
		}
		light, good := parse(components[2], 1)
		if !good {
			return ui.Color{}, false
		}
		h = math.Mod(h*factor, 360) / 60
		if h < 0 {
			h += 6
		}
		sat = max(0, min(1, sat))
		light = max(0, min(1, light))
		chroma := (1 - math.Abs(2*light-1)) * sat
		x := chroma * (1 - math.Abs(math.Mod(h, 2)-1))
		m := light - chroma/2
		switch {
		case h < 1:
			r, g = chroma, x
		case h < 2:
			r, g = x, chroma
		case h < 3:
			g, b = chroma, x
		case h < 4:
			g, b = x, chroma
		case h < 5:
			r, b = x, chroma
		default:
			r, b = chroma, x
		}
		r, g, b = (r+m)*255, (g+m)*255, (b+m)*255
	default:
		return ui.Color{}, false
	}
	return ui.RGBA(uint8(math.Round(max(0, min(255, r)))), uint8(math.Round(max(0, min(255, g)))), uint8(math.Round(max(0, min(255, b)))), float32(max(0, min(1, alpha)))), true
}
