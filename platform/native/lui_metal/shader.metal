// The Metal renderer's one shader file, as shader.glsl is the OpenGL
// one's: every scene op is an instanced quad, and the fragment shader
// computes the coverage of rounded rectangles, borders, gradients,
// stripes and shadows from signed distances, as the CPU renderer does.
// Colors are straight (not premultiplied) and blending happens in sRGB
// space.
//
// Entry points: [mainVert] + [mainFrag] draw the scene, compiled with
// DUAL defined for dual-source blending; [passVert] + [downFrag] /
// [blurFrag] compute the backdrops of effects. An effect's fragment
// shader starts from this file's declarations and adds its own
// [effectFrag] (lui_metal.effect_source).

#include <metal_stdlib>
using namespace metal;

// One instance per op, as Lui_gpu packs them: fifteen float4s.
struct Inst {
  float4 rect;      // x, y, width, height in pixels
  float4 radii;     // top-left, top-right, bottom-right, bottom-left
  float4 inner;     // radii of the border's inner edge, of the box casting a shadow, or an image's source texels
  float4 color;
  float4 color2;    // gradient end
  float4 border;    // border color
  float4 grad;      // gradient start and end points, or stripes
  float4 uv;        // texture rectangle, normalized, border widths, the box casting a shadow, or an inner shadow's hole
  float4 clip;      // the innermost clip rectangle
  float4 clipRadii;
  float4 params;    // kind, dashed or grayscale, sigma or paint, opacity
  float4 clip2;     // the clip containing the innermost one
  float4 clip2Radii;
  float4 clip3;     // the clip containing that one
  float4 clip3Radii;
};

struct Frame { float2 size; }; // the viewport, in device pixels

// The varyings a quad passes to the fragment shader: the position in
// pixels and the texture coordinates interpolate; the instance's own
// fields stay flat.
struct VOut {
  float4 pos [[position]];
  float4 point;
  float4 rect [[flat]];
  float4 radii [[flat]];
  float4 inner [[flat]];
  float4 color [[flat]];
  float4 color2 [[flat]];
  float4 border [[flat]];
  float4 grad [[flat]];
  float4 widths [[flat]];
  float4 clip [[flat]];
  float4 clipRadii [[flat]];
  float4 params [[flat]];
  float4 clip2 [[flat]];
  float4 clip2Radii [[flat]];
  float4 clip3 [[flat]];
  float4 clip3Radii [[flat]];
};

vertex VOut mainVert(const device Inst *insts [[buffer(0)]],
                     constant Frame &u [[buffer(1)]],
                     uint vid [[vertex_id]], uint iid [[instance_id]])
{
  const device Inst &in = insts[iid];
  float2 corner = float2(float(vid & 1u), float(vid >> 1u));
  float4 r = in.rect;
  float kind = in.params.x;
  if (kind < 0.5 || (kind > 3.5 && kind < 4.5) || kind > 5.5) {
    // fills, images and effects
    r = float4(r.xy - 1.0, r.zw + 2.0);
  } else if (kind < 1.5) {
    float e = 3.0 * in.params.z + 1.0;
    r = float4(r.xy - e, r.zw + 2.0 * e);
  }
  float2 p = r.xy + corner * r.zw;
  VOut o;
  o.pos = float4(p / u.size * float2(2.0, -2.0) + float2(-1.0, 1.0),
                 0.0, 1.0);
  // The texture coordinate of the pixel, relative to the op's
  // rectangle, so expanded quads keep it where it was.
  float2 uv = in.uv.xy + (p - in.rect.xy) / in.rect.zw
              * (in.uv.zw - in.uv.xy);
  o.point = float4(p, uv);
  o.rect = in.rect;
  o.radii = in.radii;
  o.inner = in.inner;
  o.color = in.color;
  o.color2 = in.color2;
  o.border = in.border;
  o.grad = in.grad;
  o.widths = in.uv;
  o.clip = in.clip;
  o.clipRadii = in.clipRadii;
  o.params = in.params;
  o.clip2 = in.clip2;
  o.clip2Radii = in.clip2Radii;
  o.clip3 = in.clip3;
  o.clip3Radii = in.clip3Radii;
  return o;
}

// The fragment output: the color and, with DUAL defined for
// dual-source blending, the source's alpha of each channel. Without
// it, subpixel glyphs blend with the mean of their subpixels.
#ifdef DUAL
struct FOut {
  float4 color [[color(0), index(0)]];
  float4 alpha [[color(0), index(1)]];
};
#else
struct FOut { float4 color [[color(0)]]; };
#endif

float sdRoundRect(float2 p, float4 rect, float4 radii) {
  float2 h = rect.zw * 0.5;
  float2 q = p - rect.xy - h;
  float r = q.x < 0.0 ? (q.y < 0.0 ? radii.x : radii.w)
                    : (q.y < 0.0 ? radii.y : radii.z);
  float2 a = abs(q) - h + r;
  return length(max(a, float2(0.0))) + min(max(a.x, a.y), 0.0) - r;
}

float coverage(float d) { return clamp(0.5 - d, 0.0, 1.0); }

// Continuous corners bend gradually from further out than quarter
// circles, as the CPU renderer computes them: the curve leaves the
// edges contExtent times the radius from the corner, blended toward
// the quarter circle of the clamped radius by how short the sides are.
constant float contExtent = 1.528665;

// The corner of radius r's value at u inside its vertical edge and v
// inside its horizontal one, a signed distance positive outside, as the
// CPU renderer's corner_dist computes it: the distance l of the
// point's place a in the curve's box to its edge, through the quartic
// P of the ratio rho of a's smaller coordinate to its larger, blended
// toward the quarter circle f2 by the sides' clamp factors (ccx, ccy).
float cornerDist(float u, float v, float r, float rh, float rv,
                 float2 size) {
  float ce = contExtent * r;
  float ccx = clamp((contExtent - size.x / (r + rh)) / (contExtent - 1.0),
                    0.0, 1.0);
  float ccy = clamp((contExtent - size.y / (r + rv)) / (contExtent - 1.0),
                    0.0, 1.0);
  float ceff = ce + (r - ce) * max(ccx, ccy);
  float ax = max(0.0, 1.0 - u / ce);
  float ay = max(0.0, 1.0 - v / ce);
  float l = length(float2(ax, ay));
  float hi = max(ax, ay);
  float rho = hi > 0.0 ? min(min(ax, ay) / hi, 1.0) : 0.0;
  float pl = (((-0.926054 * rho + 3.15601) * rho - 3.64122) * rho
              + 1.26803) * rho + 0.268531;
  float f1 = l + 1.0 - 1.0 / (1.0 - rho * rho * min(l, 1.0) * pl);
  float2 q = max(float2(0.0), float2(ax, ay) * contExtent
                 - (contExtent - 1.0));
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
float contCorner(float u, float v, float r, float rh, float rv,
                 float2 size, thread bool &curved) {
  float ce = contExtent * r;
  if (r <= 0.0 || u >= ce || v >= ce) return -1e9;
  curved = true;
  return cornerDist(u, v, r, rh, rv, size);
}

// The continuous-cornered shape's value at p: the largest of its
// corners' and the rectangle's signed distances; curved is set where a
// corner's curve reaches p, as the CPU renderer's cont_dist computes.
float contDist(float2 p, float4 rect, float4 radii,
               thread bool &curved) {
  float left = p.x - rect.x;
  float right = rect.x + rect.z - p.x;
  float top = p.y - rect.y;
  float bottom = rect.y + rect.w - p.y;
  float d = max(max(-left, -right), max(-top, -bottom));
  float4 ar = abs(radii);
  curved = false;
  d = max(d, contCorner(left, top, ar.x, ar.y, ar.w, rect.zw, curved));
  d = max(d, contCorner(right, top, ar.y, ar.x, ar.z, rect.zw, curved));
  d = max(d, contCorner(right, bottom, ar.z, ar.w, ar.y, rect.zw, curved));
  d = max(d, contCorner(left, bottom, ar.w, ar.z, ar.x, rect.zw, curved));
  return d;
}

// Coverage with continuous corners: away from their curves, the area
// of the pixel inside the rectangle; near them, the shape's value
// over the sum of its derivatives, as the CPU renderer's
// cont_coverage computes it.
float contCoverage(float2 p, float4 rect, float4 radii) {
  bool curved;
  float d = contDist(p, rect, radii, curved);
  if (!curved) {
    float2 c = clamp(min(rect.xy + rect.zw, p + 0.5)
                     - max(rect.xy, p - 0.5), 0.0, 1.0);
    return c.x * c.y;
  }
  if (abs(d) > 2.0) return d < 0.0 ? 1.0 : 0.0;
  float h = 1.0 / 16.0;
  bool cu;
  float dx = contDist(p + float2(h, 0.0), rect, radii, cu);
  float dy = contDist(p + float2(0.0, h), rect, radii, cu);
  return clamp(0.5 - d * h / max(abs(dx - d) + abs(dy - d), 1e-6),
               0.0, 1.0);
}

// rectCoverage returns how much of the pixel at p a rounded rectangle
// covers: by the distance to its edge near rounded corners, and
// exactly, the area of the pixel inside it, near square ones.
// Negative radii mark continuous corners, which the whole shape takes.
float rectCoverage(float2 p, float4 rect, float4 radii) {
  if (min(min(radii.x, radii.y), min(radii.z, radii.w)) < 0.0) {
    return contCoverage(p, rect, radii);
  }
  float2 q = p - rect.xy - rect.zw * 0.5;
  float r = q.x < 0.0 ? (q.y < 0.0 ? radii.x : radii.w)
                    : (q.y < 0.0 ? radii.y : radii.z);
  if (r > 0.0) {
    return coverage(sdRoundRect(p, rect, radii));
  }
  float2 c = clamp(min(rect.xy + rect.zw, p + 0.5) - max(rect.xy, p - 0.5),
                   0.0, 1.0);
  return c.x * c.y;
}

float4 premul(float4 c) { return float4(c.rgb * c.a, c.a); }

float3 unpremul(float4 c) { return c.a > 0.0 ? c.rgb / c.a : float3(0.0); }

// clipCoverage is how much of the pixel at p the clip stack lets
// through: the product of the three innermost clips' coverages, as the
// CPU renderer multiplies all of its clips'. (Deeper clips cut by
// their scissor bounds only.)
float clipCoverage(float2 p, VOut in) {
  return rectCoverage(p, in.clip, in.clipRadii)
       * rectCoverage(p, in.clip2, in.clip2Radii)
       * rectCoverage(p, in.clip3, in.clip3Radii);
}

// textCoverage corrects the coverage a of a glyph of straight color c
// as the CPU evaluator does: it enhances the contrast, the more the
// darker c is, and corrects for gamma with the ratios g.
float textCoverage(float a, float3 c, float contrast, float boost, float4 g) {
  float k = contrast * clamp(3.0 - 4.0 * dot(c, float3(0.30, 0.59, 0.11)),
                           0.0, 1.0) + boost;
  a = a * (k + 1.0) / (a * k + 1.0);
  float f = dot(c, float3(0.25, 0.5, 0.25));
  return clamp(a + a * (1.0 - a) * ((g.x * f + g.y) * a + (g.z * f + g.w)),
               0.0, 1.0);
}

// subpixelCoverage does the same for each subpixel of a subpixel glyph.
float3 subpixelCoverage(float3 a, float3 c, float contrast, float boost,
                        float4 g) {
  float k = contrast * clamp(3.0 - 4.0 * dot(c, float3(0.30, 0.59, 0.11)),
                           0.0, 1.0) + boost;
  a = a * (k + 1.0) / (a * k + 1.0);
  return clamp(a + a * (1.0 - a) * ((g.x * c + g.y) * a + (g.z * c + g.w)),
               float3(0.0), float3(1.0));
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

// The blurred rounded box: exact along x, four samples along y.
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
  return select(pow((c + 0.055) / 1.055, float3(2.4)), c / 12.92,
                c <= float3(0.04045));
}

float3 toSRGB(float3 c) {
  return select(1.055 * pow(max(c, float3(0.0)), float3(1.0 / 2.4)) - 0.055,
                c * 12.92, c <= float3(0.0031308));
}

float3 cbrt3(float3 v) { return sign(v) * pow(abs(v), float3(1.0 / 3.0)); }

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

// paint returns the premultiplied color at p of plain color, a
// gradient mixed in sRGB (1) or Oklab (2), or stripes (3).
float4 paint(float2 p, float mode, float4 rect, float4 c1, float4 c2, float4 g) {
  if (mode < 0.5) {
    return premul(c1);
  }
  if (mode < 2.5) {
    float2 d = g.zw - g.xy;
    float t = clamp(dot(p - g.xy, d) / max(dot(d, d), 0.0001), 0.0, 1.0);
    float a = mix(c1.a, c2.a, t);
    if (mode < 1.5) {
      return float4(mix(c1.rgb * c1.a, c2.rgb * c2.a, t), a);
    }
    float3 lab = mix(oklab(c1.rgb) * c1.a, oklab(c2.rgb) * c2.a, t);
    return a > 0.0 ? float4(clamp(fromOklab(lab / a), 0.0, 1.0) * a, a)
                   : float4(0.0);
  }
  float s = dot(p - rect.xy, g.xy);
  float phase = s - g.w * floor(s / g.w);
  float cov = coverage(min(max(-phase, phase - g.z), g.w - phase));
  return premul(c1) * cov + premul(c2) * (1.0 - cov);
}

// dash returns how much of a dashed border shows at p: each side,
// which the pixel belongs to when it is nearest that side's edge in
// widths of its border, has an odd number of dashes and gaps of equal
// length, about three widths, starting and ending with a dash.
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

// The main fragment shader. uMask is the mask atlas (R8), uColor the
// color atlas (RGBA premultiplied), uImage a batch's image (RGBA
// premultiplied).
fragment FOut mainFrag(VOut in [[stage_in]],
                       texture2d<float> uMask [[texture(0)]],
                       texture2d<float> uColor [[texture(1)]],
                       texture2d<float> uImage [[texture(2)]],
                       sampler smp [[sampler(0)]])
{
  float2 p = in.point.xy;
  float2 tex = in.point.zw;
  float kind = in.params.x;
  float4 res;
  if (kind < 0.5) {
    float outer = rectCoverage(p, in.rect, in.radii);
    res = paint(p, in.params.z, in.rect, in.color, in.color2, in.grad) * outer;
    float4 bw = in.widths; // top, right, bottom, left
    if (any(bw > float4(0.0))) {
      float4 ir = float4(in.rect.xy + bw.wx, in.rect.zw - bw.yz - bw.wx);
      float innerCov = (ir.z > 0.0 && ir.w > 0.0)
                           ? rectCoverage(p, ir, in.inner) : 0.0;
      float bc = clamp(outer - innerCov, 0.0, 1.0);
      if (in.params.y > 0.5) {
        bc *= dash(p, in.rect, bw);
      }
      float4 b = premul(in.border) * bc;
      res = b + res * (1.0 - b.a);
    }
  } else if (kind < 1.5 && in.params.y > 0.5) {
    // An inner shadow: inside the box, what the hole, blurred, leaves.
    float sigma = in.params.z;
    float hole = 0.0;
    if (in.widths.z > 0.0 && in.widths.w > 0.0) {
      float corner = max(max(in.inner.x, in.inner.y), max(in.inner.z, in.inner.w));
      hole = sigma > 0.0 ? boxShadow(p, in.widths, sigma, corner)
                         : rectCoverage(p, in.widths, in.inner);
    }
    res = premul(in.color) * (rectCoverage(p, in.rect, in.radii) * (1.0 - hole));
  } else if (kind < 1.5) {
    float sigma = in.params.z;
    float corner = max(max(in.radii.x, in.radii.y), max(in.radii.z, in.radii.w));
    float s = sigma > 0.0 ? boxShadow(p, in.rect, sigma, corner)
                          : rectCoverage(p, in.rect, in.radii);
    if (in.widths.z > 0.0 && in.widths.w > 0.0) {
      s *= 1.0 - rectCoverage(p, in.widths, in.inner); // outside the box casting it
    }
    res = premul(in.color) * s;
  } else if (kind < 2.5) {
    float4 c = paint(p, in.params.z, in.rect, in.color, in.color2, in.grad);
    res = c * textCoverage(uMask.sample(smp, tex).r, unpremul(c),
                           in.inner.x, in.inner.y, in.radii);
  } else if (kind < 3.5) {
    res = uColor.sample(smp, tex) * in.color.a;
  } else if (kind < 4.5) {
    // The bilinear sample at tex, its position clamped to the source
    // rectangle's texels, which inner holds, as the CPU renderer
    // clamps them.
    float2 sz = float2(uImage.get_width(), uImage.get_height());
    float2 t = clamp(tex * sz - 0.5, in.inner.xy, in.inner.zw);
    res = uImage.sample(smp, (t + 0.5) / sz)
          * rectCoverage(p, in.rect, in.radii);
    if (in.params.y > 0.5) {
      res.rgb = float3(dot(res.rgb, float3(0.2126, 0.7152, 0.0722)));
    }
  } else {
    float4 c = paint(p, in.params.z, in.rect, in.color, in.color2, in.grad);
    float3 straight = unpremul(c);
    float3 a = subpixelCoverage(uColor.sample(smp, tex).rgb, straight,
                                in.inner.x, in.inner.y, in.radii);
    float3 w = a * c.a * clipCoverage(p, in) * in.params.w;
    float wa = (w.r + w.g + w.b) / 3.0;
#ifdef DUAL
    FOut o;
    o.color = float4(straight * w, wa);
    o.alpha = float4(w, wa);
    return o;
#else
    FOut o;
    o.color = float4(straight * wa, wa);
    return o;
#endif
  }
  FOut o;
  o.color = res * clipCoverage(p, in) * in.params.w;
#ifdef DUAL
  o.alpha = float4(o.color.a);
#endif
  return o;
}

// The passes computing the backdrop of an effect draw a quad over
// their target, scissored to the texels they compute, and address
// texels by their index in memory, so that the rows of their textures
// go down as the frame's rows do.
struct POut { float4 pos [[position]]; };

vertex POut passVert(uint vid [[vertex_id]]) {
  POut o;
  o.pos = float4(float2(float(vid & 1u), float(vid >> 1u)) * 2.0 - 1.0,
                 0.0, 1.0);
  return o;
}

// down averages the square of the area each texel stands for,
// repeating the area's last pixels past its far edges. The source is
// the frame texture itself: Metal textures keep their rows in the
// frame's order, so texel (x, y) of the source is frame pixel
// (u.origin + x, u.origin + y).
struct DownArgs {
  int2 origin; // the area's first pixel, frame coords
  int2 limit;  // its last pixel, frame coords (inclusive)
  int down;    // the side of the squares averaged
  int pad;
};

fragment float4 downFrag(float4 pos [[position]],
                         texture2d<float> src [[texture(0)]],
                         constant DownArgs &a [[buffer(0)]])
{
  int2 o = a.origin + int2(pos.xy) * a.down;
  float4 c = float4(0.0);
  for (int y = 0; y < a.down; y++) {
    for (int x = 0; x < a.down; x++) {
      int2 at = min(o + int2(x, y), a.limit);
      c += src.read(uint2(at));
    }
  }
  return c * (1.0 / float(a.down * a.down));
}

// blur blurs along a row or a column, clamping at its ends.
struct BlurArgs {
  int2 limit; // the last texel of the source (inclusive)
  int2 dir;   // (1, 0) along rows, (0, 1) along columns
  int radius;
  float sigma;
};

fragment float4 blurFrag(float4 pos [[position]],
                         texture2d<float> src [[texture(0)]],
                         constant BlurArgs &a [[buffer(0)]])
{
  int2 at = int2(pos.xy);
  float4 c = float4(0.0);
  float sum = 0.0;
  for (int o = -a.radius; o <= a.radius; o++) {
    float x = float(o);
    float w = a.sigma > 0.0 ? exp(-(x * x) / (2.0 * a.sigma * a.sigma)) : 1.0;
    c += src.read(uint2(clamp(at + a.dir * o, int2(0), a.limit))) * w;
    sum += w;
  }
  return c / sum;
}
