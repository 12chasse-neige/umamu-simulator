shader_type sky;

uniform sampler2D day_panorama : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 sun_direction = vec3(0.5, 0.8, 0.3);
uniform float daylight = 1.0;
uniform float twilight = 0.0;

float star_hash(vec2 cell) {
	vec3 p = fract(vec3(cell.xyx) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	float altitude = max(EYEDIR.y, 0.0);
	float horizon = pow(1.0 - altitude, 4.0);
	float toward_sun = max(dot(EYEDIR, sun_direction), 0.0);
	float moon_facing = max(dot(EYEDIR, -sun_direction), 0.0);
	vec3 panorama = texture(day_panorama, SKY_COORDS).rgb * 0.94;
	vec3 night = mix(vec3(0.010, 0.018, 0.052), vec3(0.055, 0.083, 0.17), horizon);

	// Keep the panorama's cloud shapes as the blue daylight fades.
	float cloud = smoothstep(0.70, 0.88, panorama.r / max(panorama.b, 0.001));
	cloud *= smoothstep(0.015, 0.17, altitude);
	float cloud_value = smoothstep(0.35, 1.15, dot(panorama, vec3(0.21, 0.72, 0.07)));
	vec3 cloud_color = mix(vec3(0.045, 0.066, 0.114), vec3(0.12, 0.154, 0.216), cloud_value);
	cloud_color += pow(moon_facing, 18.0) * vec3(0.087, 0.105, 0.145);
	night = mix(night, cloud_color, cloud * 0.90);

	panorama *= mix(vec3(1.0), vec3(1.31, 0.83, 0.64), twilight * 0.55);
	vec3 color = mix(night, panorama, daylight);
	color += twilight * horizon * (vec3(0.22, 0.067, 0.086) +
		vec3(0.75, 0.21, 0.035) * pow(toward_sun, 5.0));

	if (!AT_CUBEMAP_PASS) {
		vec2 grid = SKY_COORDS * vec2(640.0, 320.0);
		float star = star_hash(floor(grid));
		float glint = (1.0 - smoothstep(0.04, 0.20, length(fract(grid) - 0.5)));
		color += vec3(0.68, 0.78, 1.0) * glint * smoothstep(0.997, 1.0, star)
			* (1.0 - daylight) * (1.0 - 0.97 * cloud) * smoothstep(0.04, 0.32, altitude);

		float moon = smoothstep(0.99969, 0.99979, moon_facing);
		color += (moon * (1.0 - 0.93 * cloud) * vec3(1.35, 1.46, 1.67) +
			pow(moon_facing, 230.0) * vec3(0.085, 0.13, 0.24)) * (1.0 - daylight)
			* smoothstep(-0.035, 0.08, -sun_direction.y);

		float sun_disk = smoothstep(0.99971, 0.99982, toward_sun);
		color += (sun_disk * vec3(3.1, 2.12, 1.22) +
			pow(toward_sun, 120.0) * vec3(0.26, 0.17, 0.092))
			* smoothstep(-0.025, 0.07, sun_direction.y);
	}

	COLOR = color;
}
