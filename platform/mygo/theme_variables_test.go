package luimygo

import "testing"

func TestThemeVariablesComputeBeforeInheritance(t *testing.T) {
	parent := ComputeThemeVariables(nil, map[string]string{"--base": "red", "--alias": "var(--base)"})
	computed := ComputeThemeVariables(parent, map[string]string{
		"--base": "blue", "--channels": "12 34 56", "--color": "rgb(var(--channels) / var(--alpha, var(--missing, 50%)))",
		"--cycle-a": "var(--base, var(--cycle-b))", "--cycle-b": "var(--cycle-a)",
		"--recovered": "var(--cycle-a, green)", "--initial": "initial", "--empty": "var(--missing,)",
		"--inherited": "inherit", "--quoted": `"var(--missing)"`,
	})
	for _, tc := range []struct {
		expression, want string
		valid            bool
	}{
		{"var(--alias)", "red", true},
		{"var(--base)", "blue", true},
		{"var(--color)", "rgb(12 34 56 / 50%)", true},
		{"var(--cycle-a)", "", false},
		{"var(--cycle-b)", "", false},
		{"var(--recovered)", "green", true},
		{"var(--initial, black)", "black", true},
		{"var(--empty, black)", "", true},
		{"var(--inherited)", "", false},
		{"var(--quoted)", `"var(--missing)"`, true},
		{"var(--absent, rgb(1, 2, 3))", "rgb(1, 2, 3)", true},
		{"var(--absent, var(--base)", "", false},
	} {
		t.Run(tc.expression, func(t *testing.T) {
			got, valid := ResolveThemeValue(tc.expression, computed)
			if valid != tc.valid || got != tc.want {
				t.Fatalf("got (%q, %v), want (%q, %v)", got, valid, tc.want, tc.valid)
			}
		})
	}
}
