// The one shader of the Direct3D 11 renderer, as shader.glsl is the
// OpenGL one: every scene op is an instanced quad, and the pixel shader
// computes the coverage of rounded rectangles, borders, gradients,
// stripes and shadows from signed distances, as the CPU renderer
// (lui_raster) does. Colors are straight (not premultiplied) and
// blending is dual-source: SV_Target0 carries the premultiplied color,
// SV_Target1 per-channel alphas, combined by the blend state as
// (ONE, INV_SRC1_COLOR) — (ZERO, INV_SRC1_COLOR) for hole batches.
// The renderer compiles this file once per entry point with D3DCompile
// at run time: vs, ps, passvs, downps and blurps. The pixel shaders of
// effects (scene fx) take the shared part below, with EFFECT defined,
// before their own source and a small main.

cbuffer Globals : register(b0) {
	float2 viewport;
	float2 pad;
};

// One instance per op, as lui_gpu builds them: eleven float4s.
struct Inst {
	float4 rect : RECT;        // x, y, width, height in pixels
	float4 radii : RADII;      // top-left, top-right, bottom-right, bottom-left
	float4 inner : INNER;      // radii of the border's inner edge, of the box casting a shadow, or of an inner shadow's hole
	float4 color : COLOR0;
	float4 color2 : COLOR1;    // gradient end
	float4 border : COLOR2;    // border color
	float4 grad : GRAD;        // gradient start and end points, or stripes
	float4 uv : UV;            // texture rectangle, normalized, border widths, the box casting a shadow, or an inner shadow's hole
	float4 clip : CLIP;        // the innermost clip rectangle
	float4 clipRadii : CLIPR;
	float4 params : PARAMS;    // kind, dashed or grayscale, sigma or paint, opacity
};

struct VSOut {
	float4 pos : SV_Position;
	float4 p : PIXEL;          // the position in pixels, and the texture coordinates
	nointerpolation float4 rect : RECT;
	nointerpolation float4 radii : RADII;
	nointerpolation float4 inner : INNER;
	nointerpolation float4 color : COLOR0;
	nointerpolation float4 color2 : COLOR1;
	nointerpolation float4 border : COLOR2;
	nointerpolation float4 grad : GRAD;
	nointerpolation float4 widths : UV;
	nointerpolation float4 clip : CLIP;
	nointerpolation float4 clipRadii : CLIPR;
	nointerpolation float4 params : PARAMS;
};

Texture2D maskTex : register(t0);
Texture2D colorTex : register(t1);
Texture2D imageTex : register(t2);
SamplerState samp : register(s0);

struct PSOut {
	float4 color : SV_Target0;
	float4 alpha : SV_Target1;
};

float sdRoundRect(float2 p, float4 rect, float4 radii) {
	float2 h = rect.zw * 0.5;
	float2 q = p - rect.xy - h;
	float r = q.x < 0.0 ? (q.y < 0.0 ? radii.x : radii.w) : (q.y < 0.0 ? radii.y : radii.z);
	float2 a = abs(q) - h + r;
	return length(max(a, float2(0.0, 0.0))) + min(max(a.x, a.y), 0.0) - r;
}

float coverage(float d) { return clamp(0.5 - d, 0.0, 1.0); }

float contCoverage(float2 p, float4 rect, float4 radii);

// rectCoverage returns how much of the pixel at p a rounded rectangle
// covers: by the distance to its edge near rounded corners, and exactly,
// the area of the pixel inside it, near square ones.
float rectCoverage(float2 p, float4 rect, float4 radii) {
	if (radii.x < 0.0 || radii.y < 0.0 || radii.z < 0.0 || radii.w < 0.0)
		return contCoverage(p, rect, radii);
	float2 q = p - rect.xy - rect.zw * 0.5;
	float r = q.x < 0.0 ? (q.y < 0.0 ? radii.x : radii.w) : (q.y < 0.0 ? radii.y : radii.z);
	if (r > 0.0) {
		return coverage(sdRoundRect(p, rect, radii));
	}
	float2 c = clamp(min(rect.xy + rect.zw, p + 0.5) - max(rect.xy, p - 0.5), 0.0, 1.0);
	return c.x * c.y;
}

// Continuous corners, which negative radii in the instance mean, as
// the CPU renderer's cont_coverage computes them: a corner's curve
// leaves the edges cont_extent*radius from the corner, blended toward
// a quarter circle once the side it bends along is too short for two
// curves.
static const float contExtent = 1.528665;

// The corner's value at u inside its vertical edge and v inside its
// horizontal one, positive outside — the CPU renderer's corner_dist.
// r is the corner's radius, rh and rv the radii sharing the
// horizontal and vertical edges, w and h the rectangle's sides. A
// value of -1e9 says the point is past where the curve can reach, so
// the corner contributes nothing; curved is set when it contributes.
float contCorner(float u, float v, float r, float rh, float rv,
                 float w, float h, inout bool curved) {
	if (r <= 0.0) return -1e9;
	float cx = clamp((contExtent - w / (r + rh)) / (contExtent - 1.0),
	                 0.0, 1.0);
	float cy = clamp((contExtent - h / (r + rv)) / (contExtent - 1.0),
	                 0.0, 1.0);
	float e = contExtent * r;
	float eff = e + (r - e) * max(cx, cy);
	if (u >= e || v >= e) return -1e9;
	curved = true;
	float ax = max(0.0, 1.0 - u / e);
	float ay = max(0.0, 1.0 - v / e);
	float l = sqrt(ax * ax + ay * ay);
	float hi = max(ax, ay), lo = min(ax, ay);
	float rho = hi > 0.0 ? min(lo / hi, 1.0) : 0.0;
	float poly = (((-0.926054 * rho + 3.15601) * rho - 3.64122) * rho +
	              1.26803) * rho + 0.268531;
	float f1 = l + 1.0 - 1.0 / (1.0 - rho * rho * min(l, 1.0) * poly);
	float qx = max(0.0, ax * contExtent - (contExtent - 1.0));
	float qy = max(0.0, ay * contExtent - (contExtent - 1.0));
	float f2 = sqrt(qx * qx + qy * qy) * 0.654166 + 0.345834;
	float s = ay > ax ? 1.0 : -1.0;
	float wgt = clamp(0.5 - s + s * rho, 0.0, 1.0);
	float fx = f1 + (f2 - f1) * cx, fy = f1 + (f2 - f1) * cy;
	float f = fx + (fy - fx) * wgt;
	return min(max(eff - u, eff - v), 0.0) + e * (f - 1.0);
}

// The shape's signed distance at p: the largest of the rectangle's
// edge distances and the corners' values, and whether a corner's
// curve reaches p — the CPU renderer's cont_dist.
float contDist(float2 p, float4 rect, float4 radii, inout bool curved) {
	float left = p.x - rect.x, right = rect.x + rect.z - p.x;
	float top = p.y - rect.y, bottom = rect.y + rect.w - p.y;
	float d = max(max(-left, -right), max(-top, -bottom));
	float4 ar = abs(radii);
	float w = rect.z, h = rect.w;
	d = max(d, contCorner(left, top, ar.x, ar.y, ar.w, w, h, curved));
	d = max(d, contCorner(right, top, ar.y, ar.x, ar.z, w, h, curved));
	d = max(d, contCorner(right, bottom, ar.z, ar.w, ar.y, w, h, curved));
	d = max(d, contCorner(left, bottom, ar.w, ar.z, ar.x, w, h, curved));
	return d;
}

// Coverage with continuous corners: away from their curves, the area
// of the pixel inside the rectangle; near them, the shape's value over
// the sum of its derivatives — the CPU renderer's cont_coverage.
float contCoverage(float2 p, float4 rect, float4 radii) {
	bool curved = false;
	float d = contDist(p, rect, radii, curved);
	if (!curved) {
		float2 c = clamp(min(rect.xy + rect.zw, p + 0.5) -
		                 max(rect.xy, p - 0.5), 0.0, 1.0);
		return c.x * c.y;
	}
	if (abs(d) > 2.0) return d < 0.0 ? 1.0 : 0.0;
	float h = 1.0 / 16.0;
	bool b = false;
	float dx = contDist(p + float2(h, 0.0), rect, radii, b);
	float dy = contDist(p + float2(0.0, h), rect, radii, b);
	return clamp(0.5 - d * h / max(abs(dx - d) + abs(dy - d), 1e-6),
	             0.0, 1.0);
}

float4 premul(float4 c) { return float4(c.rgb * c.a, c.a); }

float3 unpremul(float4 c) { return c.a > 0.0 ? c.rgb / c.a : float3(0.0, 0.0, 0.0); }

// What follows is the renderer's own; effects take what is above.
#ifndef EFFECT

VSOut vs(uint vid : SV_VertexID, Inst i) {
	VSOut o;
	float2 corner = float2(vid & 1, vid >> 1);
	float4 r = i.rect;
	float kind = i.params.x;
	if (kind < 0.5 || kind > 5.5) { // fills and effects
		r = float4(r.xy - 1.0, r.zw + 2.0);
	} else if (kind < 1.5) {
		float e = 3.0 * i.params.z + 1.0;
		r = float4(r.xy - e, r.zw + 2.0 * e);
	} else if (kind > 3.5 && kind < 4.5) {
		// The rasterizer only emits fragments whose pixel center is
		// inside the quad, but the edge pixels a fractional rect only
		// partially covers still draw — the quad grows to reach them
		// while tex keeps mapping the unpadded rect.
		r = float4(r.xy - 1.0, r.zw + 2.0);
	}
	float2 p = r.xy + corner * r.zw;
	o.pos = float4(p / viewport * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
	o.p = float4(p, i.uv.xy + (p - i.rect.xy) * (i.uv.zw - i.uv.xy) /
	                i.rect.zw);
	o.rect = i.rect;
	o.radii = i.radii;
	o.inner = i.inner;
	o.color = i.color;
	o.color2 = i.color2;
	o.border = i.border;
	o.grad = i.grad;
	o.widths = i.uv;
	o.clip = i.clip;
	o.clipRadii = i.clipRadii;
	o.params = i.params;
	return o;
}

// textCoverage corrects the coverage a of a glyph of straight color c as
// Direct2D blends text (scene.TextCoverage): it enhances the contrast,
// the more the darker c is, and corrects for gamma with the ratios g.
float textCoverage(float a, float3 c, float contrast, float boost, float4 g) {
	float k = contrast * clamp(3.0 - 4.0 * dot(c, float3(0.30, 0.59, 0.11)), 0.0, 1.0) + boost;
	a = a * (k + 1.0) / (a * k + 1.0);
	float f = dot(c, float3(0.25, 0.5, 0.25));
	return clamp(a + a * (1.0 - a) * ((g.x * f + g.y) * a + (g.z * f + g.w)), 0.0, 1.0);
}

// subpixelCoverage does the same for each subpixel of a subpixel glyph.
float3 subpixelCoverage(float3 a, float3 c, float contrast, float boost, float4 g) {
	float k = contrast * clamp(3.0 - 4.0 * dot(c, float3(0.30, 0.59, 0.11)), 0.0, 1.0) + boost;
	a = a * (k + 1.0) / (a * k + 1.0);
	return clamp(a + a * (1.0 - a) * ((g.x * c + g.y) * a + (g.z * c + g.w)), 0.0, 1.0);
}

// erf2 approximates the error function (Abramowitz and Stegun 7.1.27).
float2 erf2(float2 x) {
	float2 s = sign(x);
	float2 a = abs(x);
	x = 1.0 + (0.278393 + (0.230389 + 0.078108 * (a * a)) * a) * a;
	x *= x;
	return s - s / (x * x);
}

float gaussian(float x, float sigma) {
	return exp(-(x * x) / (2.0 * sigma * sigma)) / (2.50662827463 * sigma);
}

// The blurred rounded box of Evan Wallace: exact along x, four samples
// along y.
float shadowX(float x, float y, float sigma, float corner, float2 h) {
	float delta = min(h.y - corner - abs(y), 0.0);
	float curved = h.x - corner + sqrt(max(0.0, corner * corner - delta * delta));
	float2 integral = 0.5 + 0.5 * erf2((x + float2(-curved, curved)) * (sqrt(0.5) / sigma));
	return integral.y - integral.x;
}

float boxShadow(float2 p, float4 rect, float sigma, float corner) {
	float2 h = rect.zw * 0.5;
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

float3 toLinear(float3 c) {
	return (c <= 0.04045) ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

float3 toSRGB(float3 c) {
	return (c <= 0.0031308) ? c * 12.92 : 1.055 * pow(max(c, float3(0.0, 0.0, 0.0)), 1.0 / 2.4) - 0.055;
}

float3 cbrt3(float3 v) { return sign(v) * pow(abs(v), 1.0 / 3.0); }

float3 oklab(float3 srgb) {
	float3 c = toLinear(srgb);
	float3 lms = cbrt3(float3(
		0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b,
		0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b,
		0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b));
	return float3(
		0.2104542553 * lms.x + 0.7936177850 * lms.y - 0.0040720468 * lms.z,
		1.9779984951 * lms.x - 2.4285922050 * lms.y + 0.4505937099 * lms.z,
		0.0259040371 * lms.x + 0.7827717662 * lms.y - 0.8086757660 * lms.z);
}

float3 fromOklab(float3 lab) {
	float3 lms = float3(
		lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z,
		lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z,
		lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z);
	lms = lms * lms * lms;
	return toSRGB(float3(
		4.0767416621 * lms.x - 3.3077115913 * lms.y + 0.2309699292 * lms.z,
		-1.2684380046 * lms.x + 2.6097574011 * lms.y - 0.3413193965 * lms.z,
		-0.0041960863 * lms.x - 0.7034186147 * lms.y + 1.7076147010 * lms.z));
}

// paint returns the premultiplied color at p of plain color, a gradient
// mixed in sRGB (1) or Oklab (2), or stripes (3), as scene.Paint says.
float4 paint(float2 p, float mode, float4 rect, float4 c1, float4 c2, float4 g) {
	if (mode < 0.5) {
		return premul(c1);
	}
	if (mode < 2.5) {
		float2 d = g.zw - g.xy;
		float t = clamp(dot(p - g.xy, d) / max(dot(d, d), 0.0001), 0.0, 1.0);
		float a = lerp(c1.a, c2.a, t);
		if (mode < 1.5) {
			return float4(lerp(c1.rgb * c1.a, c2.rgb * c2.a, t), a);
		}
		float3 lab = lerp(oklab(c1.rgb) * c1.a, oklab(c2.rgb) * c2.a, t);
		return a > 0.0 ? float4(clamp(fromOklab(lab / a), 0.0, 1.0) * a, a) : float4(0.0, 0.0, 0.0, 0.0);
	}
	float s = dot(p - rect.xy, g.xy);
	float phase = s - g.w * floor(s / g.w);
	float cov = coverage(min(max(-phase, phase - g.z), g.w - phase));
	return premul(c1) * cov + premul(c2) * (1.0 - cov);
}

// A premultiplied pixel of the image texture at the normalized
// coordinates uv, bilinear, with the taps clamped to the source
// rectangle src — the CPU renderer's sample. Sampling the texture
// would clamp only at its edge and read pixels outside the source.
float4 imageAt(float2 uv, float4 src) {
	uint2 sz;
	imageTex.GetDimensions(sz.x, sz.y);
	float u = uv.x * (float)sz.x - 0.5;
	float v = uv.y * (float)sz.y - 0.5;
	int x0 = (int)floor(u), y0 = (int)floor(v);
	float2 t = float2(u - (float)x0, v - (float)y0);
	// The source rectangle in texels; its bounds are whole numbers in
	// practice, so a little slack corrects the float32 roundtrip.
	int2 mn = int2((int)floor(src.x * (float)sz.x + 0.001),
	               (int)floor(src.y * (float)sz.y + 0.001));
	int2 mx = int2(min((int)ceil(src.z * (float)sz.x - 0.001) - 1,
	                   (int)sz.x - 1),
	               min((int)ceil(src.w * (float)sz.y - 0.001) - 1,
	                   (int)sz.y - 1));
	float4 p00 = imageTex.Load(int3(clamp(int2(x0, y0), mn, mx), 0));
	float4 p10 = imageTex.Load(int3(clamp(int2(x0 + 1, y0), mn, mx), 0));
	float4 p01 = imageTex.Load(int3(clamp(int2(x0, y0 + 1), mn, mx), 0));
	float4 p11 = imageTex.Load(int3(clamp(int2(x0 + 1, y0 + 1), mn, mx), 0));
	return lerp(lerp(p00, p10, t.x), lerp(p01, p11, t.x), t.y);
}

// dash returns how much of a dashed border shows at p: each side, which
// the pixel belongs to when it is nearest that side's edge in widths of
// its border, has an odd number of dashes and gaps of equal length, about
// three widths, starting and ending with a dash.
float dash(float2 p, float4 rect, float4 w) {
	float2 q = p - rect.xy;
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

PSOut ps(VSOut i) {
	PSOut o;
	float2 p = i.p.xy;
	float2 tex = i.p.zw;
	float kind = i.params.x;
	float4 res;
	if (kind < 0.5) {
		float outer = rectCoverage(p, i.rect, i.radii);
		res = paint(p, i.params.z, i.rect, i.color, i.color2, i.grad) * outer;
		float4 bw = i.widths; // top, right, bottom, left
		if (any(bw > 0.0)) {
			float4 ir = float4(i.rect.xy + bw.wx, i.rect.zw - bw.yz - bw.wx);
			float innerCov = (ir.z > 0.0 && ir.w > 0.0) ? rectCoverage(p, ir, i.inner) : 0.0;
			float bc = clamp(outer - innerCov, 0.0, 1.0);
			if (i.params.y > 0.5) {
				bc *= dash(p, i.rect, bw);
			}
			float4 b = premul(i.border) * bc;
			res = b + res * (1.0 - b.a);
		}
	} else if (kind < 1.5 && i.params.y > 0.5) {
		// An inner shadow: inside the box, what the hole, blurred, leaves.
		float sigma = i.params.z;
		float hole = 0.0;
		if (i.widths.z > 0.0 && i.widths.w > 0.0) {
			float corner = max(max(i.inner.x, i.inner.y), max(i.inner.z, i.inner.w));
			hole = sigma > 0.0 ? boxShadow(p, i.widths, sigma, corner) : rectCoverage(p, i.widths, i.inner);
		}
		res = premul(i.color) * (rectCoverage(p, i.rect, i.radii) * (1.0 - hole));
	} else if (kind < 1.5) {
		float sigma = i.params.z;
		float corner = max(max(i.radii.x, i.radii.y), max(i.radii.z, i.radii.w));
		float s = sigma > 0.0 ? boxShadow(p, i.rect, sigma, corner) : rectCoverage(p, i.rect, i.radii);
		if (i.widths.z > 0.0 && i.widths.w > 0.0) {
			s *= 1.0 - rectCoverage(p, i.widths, i.inner); // outside the box casting it
		}
		res = premul(i.color) * s;
	} else if (kind < 2.5) {
		float4 c = paint(p, i.params.z, i.rect, i.color, i.color2, i.grad);
		res = c * textCoverage(maskTex.Sample(samp, tex).r, unpremul(c), i.inner.x, i.inner.y, i.radii);
	} else if (kind < 3.5) {
		res = colorTex.Sample(samp, tex) * i.color.a;
	} else if (kind < 4.5) {
		res = imageAt(tex, i.widths) * rectCoverage(p, i.rect, i.radii);
		if (i.params.y > 0.5) {
			res.rgb = dot(res.rgb, float3(0.2126, 0.7152, 0.0722)).xxx;
		}
	} else {
		float4 c = paint(p, i.params.z, i.rect, i.color, i.color2, i.grad);
		float3 straight = unpremul(c);
		float3 a = subpixelCoverage(colorTex.Sample(samp, tex).rgb, straight, i.inner.x, i.inner.y, i.radii);
		float3 w = a * c.a * rectCoverage(p, i.clip, i.clipRadii) * i.params.w;
		float wa = (w.r + w.g + w.b) / 3.0;
		o.color = float4(straight * w, wa);
		o.alpha = float4(w, wa);
		return o;
	}
	float clip = rectCoverage(p, i.clip, i.clipRadii);
	o.color = res * clip * i.params.w;
	o.alpha = o.color.aaaa;
	return o;
}

// The passes computing the backdrop of an effect draw a quad over their
// target, scissored to the texels they compute, and address texels by
// their index in memory.
cbuffer PassConstants : register(b1) {
	int2 passOrigin;
	int2 passLimit;
	int2 passShift;
	int2 passDir;
	int passDown;
	int passRadius;
	float passSigma;
	float passPad;
};

Texture2D passSrc : register(t4);

float4 passvs(uint vid : SV_VertexID) : SV_Position {
	float2 corner = float2(vid & 1, vid >> 1);
	return float4(corner * 2.0 - 1.0, 0.0, 1.0);
}

// down averages the square of the area that texel stands for, repeating
// the area's last pixels past its far edges. The frame area it reads was
// copied verbatim into passSrc, so the frame pixel at is at at - passShift.
float4 downps(float4 pos : SV_Position) : SV_Target {
	int2 o = passOrigin + int2(pos.xy) * passDown;
	float4 c = float4(0.0, 0.0, 0.0, 0.0);
	for (int y = 0; y < passDown; y++) {
		for (int x = 0; x < passDown; x++) {
			c += passSrc.Load(int3(min(o + int2(x, y), passLimit) - passShift, 0));
		}
	}
	return c * (1.0 / (float)(passDown * passDown));
}

// blur blurs along a row or a column, clamping at its ends.
float4 blurps(float4 pos : SV_Position) : SV_Target {
	int2 at = int2(pos.xy);
	float4 c = float4(0.0, 0.0, 0.0, 0.0);
	float sum = 0.0;
	for (int o = -passRadius; o <= passRadius; o++) {
		float x = (float)o;
		float w = passSigma > 0.0 ? exp(-(x * x) / (2.0 * passSigma * passSigma)) : 1.0;
		c += passSrc.Load(int3(clamp(at + passDir * o, int2(0, 0), passLimit), 0)) * w;
		sum += w;
	}
	return c / sum;
}

#endif
