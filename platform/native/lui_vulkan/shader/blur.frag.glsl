#version 450

// blur blurs along a row or a column, clamping at its ends. Same math
// as the other renderers' blur pass; texel addressing is identical
// because the pass targets and sources are stored top-down.

layout(set = 0, binding = 0) uniform sampler2D uSrc;
layout(push_constant) uniform Pass {
	ivec2 uOrigin;
	ivec2 uLimit;
	ivec2 uShift;
	ivec2 uDir;
	int uDown;
	int uRadius;
	float uSigma;
	float uPad;
} pc;

layout(location = 0) out vec4 passColor;

void main() {
	ivec2 at = ivec2(gl_FragCoord.xy);
	vec4 c = vec4(0.0);
	float sum = 0.0;
	for (int o = -pc.uRadius; o <= pc.uRadius; o++) {
		float x = float(o);
		float w = pc.uSigma > 0.0 ? exp(-(x * x) / (2.0 * pc.uSigma * pc.uSigma)) : 1.0;
		c += texelFetch(uSrc, clamp(at + pc.uDir * o, ivec2(0), pc.uLimit), 0) * w;
		sum += w;
	}
	passColor = c / sum;
}
