shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_never, shadows_disabled, ambient_light_disabled;

uniform sampler2D scene_color : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest;
uniform sampler2D daylight : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D ripple_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform bool pouring = false;
uniform bool main_basin = false;
uniform bool spray = false;
uniform float basin_depth = 0.30;
uniform float daylight_fraction : hint_range(0.0, 1.0) = 1.0;

varying vec3 world_position;

void vertex() {
	if (pouring && !spray) {
		float falling = 1.0 - UV.y;
		float wave = sin(falling * 77.0 - TIME * 17.0 + UV.x * TAU);
		VERTEX += NORMAL * wave * 0.0035 * smoothstep(0.0, 0.14, falling);
	}
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float view_depth(vec2 uv, mat4 inverse_projection) {
	float raw = textureLod(scene_depth, uv, 0.0).r;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		vec3 ndc = vec3(uv, raw) * 2.0 - 1.0;
	#else
		vec3 ndc = vec3(uv * 2.0 - 1.0, raw);
	#endif
	vec4 view_position = inverse_projection * vec4(ndc, 1.0);
	return -view_position.z / view_position.w;
}

vec3 sky_reflection(vec3 direction) {
	vec2 uv = vec2(atan(direction.x, -direction.z) / TAU + 0.5, acos(clamp(direction.y, -1.0, 1.0)) / PI);
	vec3 panorama = textureLod(daylight, uv, 0.0).rgb * 0.96;
	return mix(vec3(0.04, 0.065, 0.14) * (0.6 + 0.4 * panorama), panorama, daylight_fraction);
}

vec3 reflected_scene(vec3 origin, vec3 ray, mat4 projection, mat4 inverse_projection, vec3 sky) {
	float distance_along_ray = 0.20;
	float old_gap = 1.0;
	vec2 old_uv = vec2(0.0);
	for (int i = 0; i < 17; i++) {
		vec3 point = origin + ray * distance_along_ray;
		if (point.z >= -0.10) { break; }
		vec4 clip = projection * vec4(point, 1.0);
		vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
		if (any(lessThan(uv, vec2(0.015))) || any(greaterThan(uv, vec2(0.985)))) { break; }
		float gap = view_depth(uv, inverse_projection) + point.z;
		if (i > 0 && gap <= 0.0 && old_gap > 0.0 && gap > -3.0) {
			vec2 hit = mix(old_uv, uv, old_gap / (old_gap - gap));
			vec2 edge = min(hit, 1.0 - hit);
			float fade = smoothstep(0.015, 0.12, min(edge.x, edge.y));
			vec3 nearby = textureLod(scene_color, hit, 1.0).rgb;
			return mix(sky, nearby, fade * (1.0 - smoothstep(8.0, 24.0, distance_along_ray)));
		}
		old_gap = gap;
		old_uv = uv;
		distance_along_ray = distance_along_ray * 1.26 + 0.17;
	}
	return sky;
}

vec3 impact(vec2 position, vec2 center, float phase) {
	vec2 offset = position - center;
	float r = length(offset);
	float falloff = exp(-r * 2.35) * smoothstep(0.012, 0.065, r);
	float irregularity = 0.53 * sin(offset.x * 13.0 + offset.y * 19.0 + phase);
	float wave = cos(r * 51.0 - TIME * 13.8 + phase + irregularity) + 0.28 * sin(r * 102.0 - TIME * 23.0);
	vec2 slope = offset / max(r, 0.015) * wave * falloff * 0.23;
	return vec3(slope, falloff * exp(-r * 8.0));
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float foam = 0.0;
	float falling = 1.0 - UV.y;
	if (spray) {
		foam = 0.34 + 0.30 * sin(TIME * 17.0 + world_position.x * 28.0 + world_position.z * 31.0);
	} else if (pouring) {
		vec2 advected = vec2(UV.x * 2.0, falling * 5.5 - TIME * 2.05);
		vec2 bubbles = texture(ripple_normal, advected).rg * 2.0 - 1.0;
		n = normalize(n + vec3(bubbles * vec2(0.22, 0.34), 0.0));
		float streaks = sin(falling * 138.0 - TIME * 35.0 + sin(UV.x * TAU * 2.0) * 1.8);
		foam = (0.12 + 0.16 * smoothstep(0.12, 1.0, streaks)) * mix(0.24, 1.0, smoothstep(0.05, 0.96, falling));
	} else {
		vec2 xy = world_position.xz;
		vec2 low = texture(ripple_normal, xy * 0.83 + TIME * vec2(0.055, 0.024)).rg * 2.0 - 1.0;
		vec2 high = texture(ripple_normal, xy.yx * 1.57 + TIME * vec2(-0.041, 0.037)).gr * 2.0 - 1.0;
		vec2 slope = 0.19 * low + 0.10 * high;
		if (main_basin) {
			vec3 rings = impact(xy, vec2(-1.73, -45.77), 0.0)
				+ impact(xy, vec2(-0.19, -44.88), 1.1)
				+ impact(xy, vec2(1.69, -45.65), 2.2);
			slope += rings.xy;
			foam = clamp(rings.z * (0.38 + 0.27 * low.x), 0.0, 0.68);
		}
		n = normalize(mat3(VIEW_MATRIX) * vec3(slope.x, 1.0, slope.y));
	}
	float fresnel = 0.0204 + 0.9796 * pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 5.0);
	vec2 distorted = clamp(SCREEN_UV + n.xy * (pouring ? 0.009 : 0.017), vec2(0.001), vec2(0.999));
	float surface_depth = -VERTEX.z;
	float below = view_depth(distorted, INV_PROJECTION_MATRIX) - surface_depth;
	if (below < 0.015) {
		distorted = SCREEN_UV;
		below = view_depth(distorted, INV_PROJECTION_MATRIX) - surface_depth;
	}
	vec3 background = textureLod(scene_color, distorted, pouring ? 0.45 : 0.0).rgb;
	float depth = clamp(below, 0.0, basin_depth * 3.0);
	vec3 transmission = background * exp(-depth * vec3(0.52, 0.19, 0.25));
	vec3 ray = reflect(-VIEW, n);
	vec3 reflected = sky_reflection(mat3(INV_VIEW_MATRIX) * ray);
	if (!pouring && !spray) {
		reflected = reflected_scene(VERTEX, ray, PROJECTION_MATRIX, INV_PROJECTION_MATRIX, reflected);
	}
	vec3 aeration = vec3(0.73, 0.88, 0.90) * mix(0.19, 1.0, daylight_fraction);
	EMISSION = mix(mix(transmission, reflected, fresnel), aeration, foam);
	NORMAL = n;
	ALBEDO = vec3(0.0);
	SPECULAR = 0.27;
	ROUGHNESS = pouring ? 0.11 : 0.075;
	ALPHA = spray ? clamp(foam + 0.22, 0.20, 0.78) : 1.0;
}
