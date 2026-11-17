// The shared fragment code of the Vulkan scene shader: the same math
// the CPU renderer evaluates — rounded-rect signed distances for
// coverage, premultiplied paints and gradients, dashed borders,
// gaussian box shadows, glyph coverage correction — over Lui_gpu's
// instance encoding (eleven float4s per instance). Concatenated with a
// `void main` to form a complete shader: scene_main.glsl for the scene
// pipeline, effect_head + effect body + effect_tail for runtime-
// compiled effect pipelines.

layout(location = 0) in vec4 vPoint; // the position in pixels, and the texture coordinates
layout(location = 1) flat in vec4 vRect;
layout(location = 2) flat in vec4 vRadii;
layout(location = 3) flat in vec4 vInner;
layout(location = 4) flat in vec4 vColor;
layout(location = 5) flat in vec4 vColor2;
layout(location = 6) flat in vec4 vBorder;
layout(location = 7) flat in vec4 vGrad;
layout(location = 8) flat in vec4 vWidths;
layout(location = 9) flat in vec4 vClip;
layout(location = 10) flat in vec4 vClipRadii;
layout(location = 11) flat in vec4 vClip2;
layout(location = 12) flat in vec4 vClip2Radii;
layout(location = 13) flat in vec4 vClip3;
layout(location = 14) flat in vec4 vClip3Radii;
layout(location = 15) flat in vec4 vParams;

layout(set = 0, binding = 0) uniform sampler2D uMask;
layout(set = 0, binding = 1) uniform sampler2D uColor;
layout(set = 1, binding = 0) uniform sampler2D uImage;
layout(set = 1, binding = 1) uniform sampler2D uBackdrop;

// The color and, for dual-source blending, the source's alpha of each
// channel. Without it, subpixel glyphs blend with their mean coverage.
#ifdef DUAL
layout(location = 0, index = 0) out vec4 fragColor;
layout(location = 0, index = 1) out vec4 fragAlpha;
#else
layout(location = 0) out vec4 fragColor;
#endif

float sdRoundRect(vec2 p, vec4 rect, vec4 radii) {
	vec2 h = rect.zw * 0.5;
	vec2 q = p - rect.xy - h;
	float r = q.x < 0.0 ? (q.y < 0.0 ? radii.x : radii.w) : (q.y < 0.0 ? radii.y : radii.z);
	vec2 a = abs(q) - h + r;
	return length(max(a, vec2(0.0))) + min(max(a.x, a.y), 0.0) - r;
}

float coverage(float d) { return clamp(0.5 - d, 0.0, 1.0); }

// Continuous corners bend gradually from further out than quarter
// circles, as the CPU renderer computes them: the curve leaves the
// edges cont_extent times the radius from the corner, blended toward
// the quarter circle of the clamped radius by how short the sides are.
const float contExtent = 1.528665;

// The corner of radius r's value at u inside its vertical edge and v
// inside its horizontal one, a signed distance positive outside, as the
// CPU renderer's corner_dist computes it: the distance l of the point's
// place a in the curve's box to its edge, through the quartic P of the
// ratio rho of a's smaller coordinate to its larger, blended toward the
// quarter circle f2 by the sides' clamp factors (ccx, ccy).
float cornerDist(float u, float v, float r, float rh, float rv, vec2 size) {
	float ce = contExtent * r;
	float ccx = clamp((contExtent - size.x / (r + rh)) / (contExtent - 1.0), 0.0, 1.0);
	float ccy = clamp((contExtent - size.y / (r + rv)) / (contExtent - 1.0), 0.0, 1.0);
	float ceff = ce + (r - ce) * max(ccx, ccy);
	float ax = max(0.0, 1.0 - u / ce);
	float ay = max(0.0, 1.0 - v / ce);
	float l = length(vec2(ax, ay));
	float hi = max(ax, ay);
	float rho = hi > 0.0 ? min(min(ax, ay) / hi, 1.0) : 0.0;
	float pl = (((-0.926054 * rho + 3.15601) * rho - 3.64122) * rho + 1.26803) * rho + 0.268531;
	float f1 = l + 1.0 - 1.0 / (1.0 - rho * rho * min(l, 1.0) * pl);
	vec2 q = max(vec2(0.0), vec2(ax, ay) * contExtent - (contExtent - 1.0));
	float f2 = length(q) * 0.654166 + 0.345834;
	// The clamp along the edge the point is nearer to, blended across
	// the diagonal.
	float s = ay > ax ? 1.0 : -1.0;
	float w = clamp(0.5 - s + s * rho, 0.0, 1.0);
	float f = mix(f1 + (f2 - f1) * ccx, f1 + (f2 - f1) * ccy, w);
	return min(max(ceff - u, ceff - v), 0.0) + ce * (f - 1.0);
}

// The value one corner adds to the shape at u, v inside its edges,
// -1e9 where its curve does not reach, as cont_dist's loop computes.
float contCorner(float u, float v, float r, float rh, float rv, vec2 size, inout bool curved) {
	float ce = contExtent * r;
	if (r <= 0.0 || u >= ce || v >= ce) return -1e9;
	curved = true;
	return cornerDist(u, v, r, rh, rv, size);
}

// The continuous-cornered shape's value at p: the largest of its
// corners' and the rectangle's signed distances; curved is set where a
// corner's curve reaches p, as the CPU renderer's cont_dist computes.
float contDist(vec2 p, vec4 rect, vec4 radii, inout bool curved) {
	float left = p.x - rect.x;
	float right = rect.x + rect.z - p.x;
	float top = p.y - rect.y;
	float bottom = rect.y + rect.w - p.y;
	float d = max(max(-left, -right), max(-top, -bottom));
	vec4 ar = abs(radii);
	curved = false;
	d = max(d, contCorner(left, top, ar.x, ar.y, ar.w, rect.zw, curved));
	d = max(d, contCorner(right, top, ar.y, ar.x, ar.z, rect.zw, curved));
	d = max(d, contCorner(right, bottom, ar.z, ar.w, ar.y, rect.zw, curved));
	d = max(d, contCorner(left, bottom, ar.w, ar.z, ar.x, rect.zw, curved));
	return d;
}

// Coverage with continuous corners: away from their curves, the area
// of the pixel inside the rectangle; near them, the shape's value over
// the sum of its derivatives, as the CPU renderer's cont_coverage
// computes it.
float contCoverage(vec2 p, vec4 rect, vec4 radii) {
	bool curved;
	float d = contDist(p, rect, radii, curved);
	if (!curved) {
		vec2 c = clamp(min(rect.xy + rect.zw, p + 0.5) - max(rect.xy, p - 0.5), 0.0, 1.0);
		return c.x * c.y;
	}
	if (abs(d) > 2.0) return d < 0.0 ? 1.0 : 0.0;
	float h = 1.0 / 16.0;
	bool cu;
	float dx = contDist(p + vec2(h, 0.0), rect, radii, cu);
	float dy = contDist(p + vec2(0.0, h), rect, radii, cu);
	return clamp(0.5 - d * h / max(abs(dx - d) + abs(dy - d), 1e-6), 0.0, 1.0);
}

// rectCoverage returns how much of the pixel at p a rounded rectangle
// covers: by the distance to its edge near rounded corners, and exactly,
// the area of the pixel inside it, near square ones. Negative radii
// mark continuous corners, which the whole shape takes.
float rectCoverage(vec2 p, vec4 rect, vec4 radii) {
	if (min(min(radii.x, radii.y), min(radii.z, radii.w)) < 0.0) {
		return contCoverage(p, rect, radii);
	}
	vec2 q = p - rect.xy - rect.zw * 0.5;
	float r = q.x < 0.0 ? (q.y < 0.0 ? radii.x : radii.w) : (q.y < 0.0 ? radii.y : radii.z);
	if (r > 0.0) {
		return coverage(sdRoundRect(p, rect, radii));
	}
	vec2 c = clamp(min(rect.xy + rect.zw, p + 0.5) - max(rect.xy, p - 0.5), 0.0, 1.0);
	return c.x * c.y;
}

// clipCoverage is how much of the pixel at p the clip stack lets
// through: the product of the three innermost clips' coverages, as the
// CPU renderer multiplies all of its clips'. (Deeper clips cut by
// their scissor bounds only.)
float clipCoverage(vec2 p) {
	return rectCoverage(p, vClip, vClipRadii)
		* rectCoverage(p, vClip2, vClip2Radii)
		* rectCoverage(p, vClip3, vClip3Radii);
}

vec4 premul(vec4 c) { return vec4(c.rgb * c.a, c.a); }

vec3 unpremul(vec4 c) { return c.a > 0.0 ? c.rgb / c.a : vec3(0.0); }

// textCoverage corrects the coverage a of a glyph of straight color c as
// Direct2D blends text (scene.TextCoverage): it enhances the contrast,
// the more the darker c is, and corrects for gamma with the ratios g.
float textCoverage(float a, vec3 c, float contrast, float boost, vec4 g) {
	float k = contrast * clamp(3.0 - 4.0 * dot(c, vec3(0.30, 0.59, 0.11)), 0.0, 1.0) + boost;
	a = a * (k + 1.0) / (a * k + 1.0);
	float f = dot(c, vec3(0.25, 0.5, 0.25));
	return clamp(a + a * (1.0 - a) * ((g.x * f + g.y) * a + (g.z * f + g.w)), 0.0, 1.0);
}

// subpixelCoverage does the same for each subpixel of a subpixel glyph.
vec3 subpixelCoverage(vec3 a, vec3 c, float contrast, float boost, vec4 g) {
	float k = contrast * clamp(3.0 - 4.0 * dot(c, vec3(0.30, 0.59, 0.11)), 0.0, 1.0) + boost;
	a = a * (k + 1.0) / (a * k + 1.0);
	return clamp(a + a * (1.0 - a) * ((g.x * c + g.y) * a + (g.z * c + g.w)), vec3(0.0), vec3(1.0));
}

// erf2 approximates the error function (Abramowitz and Stegun 7.1.27).
vec2 erf2(vec2 x) {
	vec2 s = sign(x);
	vec2 a = abs(x);
	x = 1.0 + (0.278393 + (0.230389 + 0.078108 * (a * a)) * a) * a;
	x *= x;
	return s - s / (x * x);
}

float gaussian(float x, float sigma) {
	return exp(-(x * x) / (2.0 * sigma * sigma)) / (2.50662827463 * sigma);
}

// The blurred rounded box of Evan Wallace: exact along x, four samples
// along y.
float shadowX(float x, float y, float sigma, float corner, vec2 h) {
	float delta = min(h.y - corner - abs(y), 0.0);
	float curved = h.x - corner + sqrt(max(0.0, corner * corner - delta * delta));
	vec2 integral = 0.5 + 0.5 * erf2((x + vec2(-curved, curved)) * (sqrt(0.5) / sigma));
	return integral.y - integral.x;
}

float boxShadow(vec2 p, vec4 rect, float sigma, float corner) {
	vec2 h = rect.zw * 0.5;
	p -= rect.xy + h;
	float low = p.y - h.y;
	float high = p.y + h.y;
	float y0 = clamp(-3.0 * sigma, low, high);
	float y1 = clamp(3.0 * sigma, low, high);
	float dy = (y1 - y0) / 4.0;
	float y = y0 + dy * 0.5;
	float v = 0.0;
	for (int k = 0; k < 4; k++) {
		v += shadowX(p.x, p.y - y, sigma, corner, h) * gaussian(y, sigma) * dy;
		y += dy;
	}
	return v;
}

vec3 toLinear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThanEqual(c, vec3(0.04045)));
}

vec3 toSRGB(vec3 c) {
	return mix(1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, c * 12.92, lessThanEqual(c, vec3(0.0031308)));
}

vec3 cbrt3(vec3 v) { return sign(v) * pow(abs(v), vec3(1.0 / 3.0)); }

vec3 oklab(vec3 srgb) {
	vec3 c = toLinear(srgb);
	vec3 lms = cbrt3(vec3(
		0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b,
		0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b,
		0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b));
	return vec3(
		0.2104542553 * lms.x + 0.7936177850 * lms.y - 0.0040720468 * lms.z,
		1.9779984951 * lms.x - 2.4285922050 * lms.y + 0.4505937099 * lms.z,
		0.0259040371 * lms.x + 0.7827717662 * lms.y - 0.8086757660 * lms.z);
}

vec3 fromOklab(vec3 lab) {
	vec3 lms = vec3(
		lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z,
		lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z,
		lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z);
	lms = lms * lms * lms;
	return toSRGB(vec3(
		4.0767416621 * lms.x - 3.3077115913 * lms.y + 0.2309699292 * lms.z,
		-1.2684380046 * lms.x + 2.6097574011 * lms.y - 0.3413193965 * lms.z,
		-0.0041960863 * lms.x - 0.7034186147 * lms.y + 1.7076147010 * lms.z));
}

// paint returns the premultiplied color at p of plain color, a gradient
// mixed in sRGB (1) or Oklab (2), or stripes (3), as scene.Paint says.
vec4 paint(vec2 p, float mode, vec4 rect, vec4 c1, vec4 c2, vec4 g) {
	if (mode < 0.5) {
		return premul(c1);
	}
	if (mode < 2.5) {
		vec2 d = g.zw - g.xy;
		float t = clamp(dot(p - g.xy, d) / max(dot(d, d), 0.0001), 0.0, 1.0);
		float a = mix(c1.a, c2.a, t);
		if (mode < 1.5) {
			return vec4(mix(c1.rgb * c1.a, c2.rgb * c2.a, t), a);
		}
		vec3 lab = mix(oklab(c1.rgb) * c1.a, oklab(c2.rgb) * c2.a, t);
		return a > 0.0 ? vec4(clamp(fromOklab(lab / a), 0.0, 1.0) * a, a) : vec4(0.0);
	}
	float s = dot(p - rect.xy, g.xy);
	float phase = s - g.w * floor(s / g.w);
	float cov = coverage(min(max(-phase, phase - g.z), g.w - phase));
	return premul(c1) * cov + premul(c2) * (1.0 - cov);
}

// dash returns how much of a dashed border shows at p: each side, which
// the pixel belongs to when it is nearest that side's edge in widths of
// its border, has an odd number of dashes and gaps of equal length, about
// three widths, starting and ending with a dash.
float dash(vec2 p, vec4 rect, vec4 w) {
	vec2 q = p - rect.xy;
	float dt = w.x > 0.0 ? q.y / w.x : 1e9;
	float dr = w.y > 0.0 ? (rect.z - q.x) / w.y : 1e9;
	float db = w.z > 0.0 ? (rect.w - q.y) / w.z : 1e9;
	float dl = w.w > 0.0 ? q.x / w.w : 1e9;
	float s;
	float len;
	float bw;
	if (dt <= dr && dt <= db && dt <= dl) {
		s = q.x; len = rect.z; bw = w.x;
	} else if (dr <= db && dr <= dl) {
		s = q.y; len = rect.w; bw = w.y;
	} else if (db <= dl) {
		s = rect.z - q.x; len = rect.z; bw = w.z;
	} else {
		s = rect.w - q.y; len = rect.w; bw = w.w;
	}
	// n - 1 is how many periods of a dash and a gap, six widths, fit in
	// len: GPUs divide less exactly than CPUs, and may count one too few
	// or too many where len is a whole number of periods, as sides often
	// are, so the count is checked by multiplying back.
	float n = max(1.0, floor((len / (3.0 * bw) + 1.0) * 0.5 + 0.5));
	float period = 6.0 * bw;
	n += n * period <= len ? 1.0 : 0.0;
	n -= (n - 1.0) * period > len ? 1.0 : 0.0;
	float seg = len / (2.0 * n - 1.0);
	float k = floor(s / seg);
	float f = s - k * seg;
	float edge = min(f, seg - f);
	return coverage(k - 2.0 * floor(k * 0.5) < 0.5 ? -edge : edge);
}
