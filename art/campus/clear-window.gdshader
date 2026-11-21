shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_never, shadows_disabled;

void fragment() {
	float facing = max(dot(normalize(NORMAL), VIEW), 0.0);
	float reflection = 0.04 + 0.96 * pow(1.0 - facing, 5.0);
	ALBEDO = vec3(0.63, 0.71, 0.74);
	ROUGHNESS = 0.042;
	SPECULAR = 0.5;
	ALPHA = reflection * 0.62;
}
