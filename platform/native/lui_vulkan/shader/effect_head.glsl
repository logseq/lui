// The declaration part of a runtime-compiled effect fragment shader:
// appended to common.glsl (with `#define EFFECT`), followed by the
// effect's own GLSL body (a `vec4 effect(vec2 p, Effect e)` function)
// and effect_tail.glsl.

// What an effect reads of its instance.
struct Effect {
	vec4 rect;  // x, y, width, height in pixels
	vec4 radii; // top-left, top-right, bottom-right, bottom-left, circular
	vec4 p0, p1, p2, p3, p4;
	vec4 area;  // where the backdrop's area starts in the frame, and its size in texels
	float down; // the size of the squares the backdrop averages
};

vec3 backdropAt(ivec2 p, ivec2 size) {
	return texelFetch(uBackdrop, clamp(p, ivec2(0), size - 1), 0).rgb;
}

// sampleBackdrop returns the backdrop at q, in the frame's pixels,
// premultiplied, filtered bilinearly from its texels as
// scene.backdrop_sample does.
vec3 sampleBackdrop(Effect e, vec2 q) {
	vec2 u = (q - e.area.xy) / e.down - 0.5;
	vec2 f = floor(u);
	vec2 w = u - f;
	ivec2 p = ivec2(f);
	ivec2 size = ivec2(e.area.zw);
	vec3 top = backdropAt(p, size) * (1.0 - w.x)
		 + backdropAt(p + ivec2(1, 0), size) * w.x;
	vec3 bot = backdropAt(p + ivec2(0, 1), size) * (1.0 - w.x)
		 + backdropAt(p + ivec2(1, 1), size) * w.x;
	return top * (1.0 - w.y) + bot * w.y;
}
