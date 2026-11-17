#version 450

// down averages the square of the area that texel stands for, repeating
// the area's last pixels past its far edges. The area of the frame (from
// uOrigin to uLimit) is copied to uSrc top row first: the row y of the
// frame is y - uShift.y there, and the column x is x - uShift.x. (The GL
// renderer copies its area from the bottom row up, so the GL shader
// reads uShift.y - y; the Vulkan frame is stored top-down, so this
// shader reads y - uShift.y instead — the pixels sampled are identical.)

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
	ivec2 o = pc.uOrigin + ivec2(gl_FragCoord.xy) * pc.uDown;
	vec4 c = vec4(0.0);
	for (int y = 0; y < pc.uDown; y++) {
		for (int x = 0; x < pc.uDown; x++) {
			ivec2 at = min(o + ivec2(x, y), pc.uLimit);
			c += texelFetch(uSrc, ivec2(at.x - pc.uShift.x, at.y - pc.uShift.y), 0);
		}
	}
	passColor = c * (1.0 / float(pc.uDown * pc.uDown));
}
