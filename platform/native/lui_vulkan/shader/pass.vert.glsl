#version 450

// The vertex stage of the backdrop passes: a triangle-strip quad
// covering its target whole; the fragments address texels by index.

void main() {
	vec2 corner = vec2(float(gl_VertexIndex & 1), float(gl_VertexIndex >> 1));
	gl_Position = vec4(corner * 2.0 - 1.0, 0.0, 1.0);
}
