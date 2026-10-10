// The main of a runtime-compiled effect fragment shader: appended
// after the effect's own `effect` function.

void main() {
	vec2 p = vPoint.xy;
	Effect e = Effect(vRect, abs(vRadii), vInner, vColor, vColor2,
		vBorder, vGrad, vWidths, vParams.z);
	fragColor = effect(p, e) * (rectCoverage(p, vRect, vRadii)
		 * clipCoverage(p) * vParams.w);
#ifdef DUAL
	fragAlpha = fragColor.aaaa;
#endif
}
