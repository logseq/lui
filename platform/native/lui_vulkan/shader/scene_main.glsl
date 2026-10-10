// The main of the Vulkan scene fragment shader: prepended to
// common.glsl (after its `#version 450` and optional `#define DUAL`)
// to form the scene pipeline's fragment stage.

void main() {
	vec2 p = vPoint.xy;
	vec2 tex = vPoint.zw;
	float kind = vParams.x;
	vec4 res;
	if (kind < 0.5) {
		float outer = rectCoverage(p, vRect, vRadii);
		res = paint(p, vParams.z, vRect, vColor, vColor2, vGrad) * outer;
		vec4 bw = vWidths; // top, right, bottom, left
		if (any(greaterThan(bw, vec4(0.0)))) {
			vec4 ir = vec4(vRect.xy + bw.wx, vRect.zw - bw.yz - bw.wx);
			float innerCov = (ir.z > 0.0 && ir.w > 0.0) ? rectCoverage(p, ir, vInner) : 0.0;
			float bc = clamp(outer - innerCov, 0.0, 1.0);
			if (vParams.y > 0.5) {
				bc *= dash(p, vRect, bw);
			}
			vec4 b = premul(vBorder) * bc;
			res = b + res * (1.0 - b.a);
		}
	} else if (kind < 1.5 && vParams.y > 0.5) {
		// An inner shadow: inside the box, what the hole, blurred, leaves.
		float sigma = vParams.z;
		float hole = 0.0;
		if (vWidths.z > 0.0 && vWidths.w > 0.0) {
			float corner = max(max(vInner.x, vInner.y), max(vInner.z, vInner.w));
			hole = sigma > 0.0 ? boxShadow(p, vWidths, sigma, corner) : rectCoverage(p, vWidths, vInner);
		}
		res = premul(vColor) * (rectCoverage(p, vRect, vRadii) * (1.0 - hole));
	} else if (kind < 1.5) {
		float sigma = vParams.z;
		float corner = max(max(vRadii.x, vRadii.y), max(vRadii.z, vRadii.w));
		float s = sigma > 0.0 ? boxShadow(p, vRect, sigma, corner) : rectCoverage(p, vRect, vRadii);
		if (vWidths.z > 0.0 && vWidths.w > 0.0) {
			s *= 1.0 - rectCoverage(p, vWidths, vInner); // outside the box casting it
		}
		res = premul(vColor) * s;
	} else if (kind < 2.5) {
		vec4 c = paint(p, vParams.z, vRect, vColor, vColor2, vGrad);
		res = c * textCoverage(texture(uMask, tex).r, unpremul(c), vInner.x, vInner.y, vRadii);
	} else if (kind < 3.5) {
		res = texture(uColor, tex) * vColor.a;
	} else if (kind < 4.5) {
		// The bilinear sample at tex, its taps clamped to the source
		// rectangle's texels, which vInner holds, as the CPU renderer
		// clamps them.
		vec2 sz = vec2(textureSize(uImage, 0));
		vec2 t = clamp(tex * sz - 0.5, vInner.xy, vInner.zw);
		res = texture(uImage, (t + 0.5) / sz) * rectCoverage(p, vRect, vRadii);
		if (vParams.y > 0.5) {
			res.rgb = vec3(dot(res.rgb, vec3(0.2126, 0.7152, 0.0722)));
		}
	} else {
		vec4 c = paint(p, vParams.z, vRect, vColor, vColor2, vGrad);
		vec3 straight = unpremul(c);
		vec3 a = subpixelCoverage(texture(uColor, tex).rgb, straight, vInner.x, vInner.y, vRadii);
		vec3 w = a * c.a * clipCoverage(p) * vParams.w;
		float wa = (w.r + w.g + w.b) / 3.0;
#ifdef DUAL
		fragColor = vec4(straight * w, wa);
		fragAlpha = vec4(w, wa);
#else
		fragColor = vec4(straight * wa, wa);
#endif
		return;
	}
	fragColor = res * clipCoverage(p) * vParams.w;
#ifdef DUAL
	fragAlpha = fragColor.aaaa;
#endif
}
