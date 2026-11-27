shader_type spatial;

uniform bool mudland = false;
varying vec2 ground_position;

float hash_cell(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

float texture_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 blend = smoothstep(vec2(0.0), vec2(1.0), fract(p));
	return mix(
		mix(hash_cell(cell), hash_cell(cell + vec2(1.0, 0.0)), blend.x),
		mix(hash_cell(cell + vec2(0.0, 1.0)), hash_cell(cell + 1.0), blend.x),
		blend.y
	);
}

void vertex() {
	ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float grain = texture_noise(ground_position * 36.0);
	float patches = texture_noise(ground_position * 1.8);
	if (mudland) {
		ALBEDO = mix(vec3(0.14, 0.068, 0.034), vec3(0.31, 0.18, 0.088), patches * 0.8 + grain * 0.2);
		ROUGHNESS = mix(0.46, 0.93, patches);
	} else {
		float stripe = 0.5 + 0.5 * cos(ground_position.x * 1.35);
		ALBEDO = mix(vec3(0.073, 0.19, 0.043), vec3(0.17, 0.30, 0.071), stripe * 0.42 + grain * 0.42 + patches * 0.16);
		ROUGHNESS = 0.97;
	}
}
