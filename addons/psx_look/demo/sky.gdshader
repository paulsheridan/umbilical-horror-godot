shader_type sky;
// ProceduralSkyMaterial's dusk with the sun given rather than read off the light: Compatibility
// hands a sky shader no lights (4.3 to 4.7), and its sunset glow was gone there. It also hands
// colours over and takes COLOR back in sRGB, so `srgb` (a sky shader has no OUTPUT_IS_SRGB) has
// the gradient worked in linear as Forward+'s is, or its middle goes dark.

uniform vec4 top_color : source_color;
uniform vec4 horizon_color : source_color;
uniform vec4 ground_horizon_color : source_color;
uniform vec4 ground_bottom_color : source_color;
uniform vec4 sun_color : source_color;
uniform float sun_energy = 1.0;
// toward the sun
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform bool srgb = false;

vec3 linear(vec3 c) {
	return srgb ? mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c)) : c;
}

void sky() {
	float v = acos(clamp(EYEDIR.y, -1.0, 1.0));
	float c = 1.0 - v / (PI * 0.5);
	vec3 sky = mix(linear(horizon_color.rgb), linear(top_color.rgb), clamp(1.0 - pow(1.0 - c, 1.0 / 0.15), 0.0, 1.0));
	float sun = acos(clamp(dot(normalize(sun_direction), EYEDIR), -1.0, 1.0));
	float near = clamp((sun - radians(1.0)) / radians(29.0), 0.0, 1.0);
	sky = mix(linear(sun_color.rgb) * sun_energy, sky, clamp(1.0 - pow(1.0 - near, 1.0 / 0.15), 0.0, 1.0));
	float g = (v - PI * 0.5) / (PI * 0.5);
	vec3 ground = mix(linear(ground_horizon_color.rgb), linear(ground_bottom_color.rgb),
			clamp(1.0 - pow(1.0 - g, 1.0 / 0.02), 0.0, 1.0));
	vec3 col = mix(ground, sky, step(0.0, EYEDIR.y));
	COLOR = srgb ? mix(col * 12.92, 1.055 * pow(col, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, col)) : col;
}
