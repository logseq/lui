#version 450

// The Vulkan vertex stage of the shared scene shader: every scene op
// is an instanced quad, and the fragment stage computes coverage of
// rounded rectangles, borders, gradients, stripes and shadows from
// signed distances, as the CPU renderer does. The instance layout is
// Lui_gpu's: fifteen float4s per instance.
//
// Vulkan's NDC y axis points down, where the shader math was written
// for y up; the renderer binds a negative viewport height, which flips
// the clip-space y back, so the math below stays verbatim and frames
// come out top-down.

layout(location = 0) in vec4 aRect;      // x, y, width, height in pixels
layout(location = 1) in vec4 aRadii;     // top-left, top-right, bottom-right, bottom-left
layout(location = 2) in vec4 aInner;     // radii of the border's inner edge, of the box casting a shadow, or of an inner shadow's hole
layout(location = 3) in vec4 aColor;
layout(location = 4) in vec4 aColor2;    // gradient end
layout(location = 5) in vec4 aBorder;    // border color
layout(location = 6) in vec4 aGrad;      // gradient start and end points, or stripes
layout(location = 7) in vec4 aUV;        // texture rectangle, normalized, border widths, the box casting a shadow, or an inner shadow's hole
layout(location = 8) in vec4 aClip;      // the innermost clip rectangle
layout(location = 9) in vec4 aClipRadii;
layout(location = 10) in vec4 aParams;   // kind, dashed or grayscale, sigma or paint, opacity
layout(location = 11) in vec4 aClip2;    // the clip containing the innermost one
layout(location = 12) in vec4 aClip2Radii;
layout(location = 13) in vec4 aClip3;    // the clip containing that one
layout(location = 14) in vec4 aClip3Radii;

layout(push_constant) uniform Push {
	vec2 uSize;
} pc;

layout(location = 0) out vec4 vPoint; // the position in pixels, and the texture coordinates
layout(location = 1) flat out vec4 vRect;
layout(location = 2) flat out vec4 vRadii;
layout(location = 3) flat out vec4 vInner;
layout(location = 4) flat out vec4 vColor;
layout(location = 5) flat out vec4 vColor2;
layout(location = 6) flat out vec4 vBorder;
layout(location = 7) flat out vec4 vGrad;
layout(location = 8) flat out vec4 vWidths;
layout(location = 9) flat out vec4 vClip;
layout(location = 10) flat out vec4 vClipRadii;
layout(location = 11) flat out vec4 vClip2;
layout(location = 12) flat out vec4 vClip2Radii;
layout(location = 13) flat out vec4 vClip3;
layout(location = 14) flat out vec4 vClip3Radii;
layout(location = 15) flat out vec4 vParams;

void main() {
	vec2 corner = vec2(float(gl_VertexIndex & 1), float(gl_VertexIndex >> 1));
	vec4 r = aRect;
	float kind = aParams.x;
	if (kind < 0.5 || (kind > 3.5 && kind < 4.5) || kind > 5.5) { // fills, images and effects
		r = vec4(r.xy - 1.0, r.zw + 2.0);
	} else if (kind < 1.5) {
		float e = 3.0 * aParams.z + 1.0;
		r = vec4(r.xy - e, r.zw + 2.0 * e);
	}
	vec2 p = r.xy + corner * r.zw;
	gl_Position = vec4(p / pc.uSize * vec2(2.0, -2.0) + vec2(-1.0, 1.0), 0.0, 1.0);
	// The texture coordinate of the pixel, relative to the op's
	// rectangle, so expanded quads keep it where it was.
	vec2 uv = aUV.xy + (p - aRect.xy) / aRect.zw * (aUV.zw - aUV.xy);
	vPoint = vec4(p, uv);
	vRect = aRect;
	vRadii = aRadii;
	vInner = aInner;
	vColor = aColor;
	vColor2 = aColor2;
	vBorder = aBorder;
	vGrad = aGrad;
	vWidths = aUV;
	vClip = aClip;
	vClipRadii = aClipRadii;
	vClip2 = aClip2;
	vClip2Radii = aClip2Radii;
	vClip3 = aClip3;
	vClip3Radii = aClip3Radii;
	vParams = aParams;
}
