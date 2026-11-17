shader_type canvas_item;
// PSXScreen's colour: the PS1's 15-bit colour (5 bits a channel) and its 4x4 ordered dither,
// on the low-resolution picture's own pixels, after its saturation and tint; and a CRT's dark
// gaps between its lines. Each channel goes to its nearest step (round), not down (floor, as the
// PS1's GPU truncated), which crushed the darkest steps to black and lifted the lights; half a unit
// centres the PS1's -4 to +3 matrix, so a colour on a step shows flat, not dithered.

uniform bool dither = true;
uniform int color_bits : hint_range(1, 8) = 5;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float scanlines : hint_range(0.0, 1.0) = 0.0;

const mat4 PS1_DITHER = mat4(
	vec4(-4.0, 2.0, -3.0, 3.0),
	vec4(0.0, -2.0, 1.0, -1.0),
	vec4(-3.0, 3.0, -4.0, 2.0),
	vec4(1.0, -1.0, 0.0, -2.0));

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	c.rgb = mix(vec3(dot(c.rgb, vec3(0.299, 0.587, 0.114))), c.rgb, saturation) * tint.rgb;
	float steps = exp2(float(color_bits));
	float size = 256.0 / steps;
	ivec2 p = ivec2(floor(UV / TEXTURE_PIXEL_SIZE)) & ivec2(3);
	float d = dither ? (PS1_DITHER[p.x][p.y] + 0.5) * size / 8.0 : 0.0;
	vec3 v = clamp(round((c.rgb * 255.0 + d) / 255.0 * (steps - 1.0)), 0.0, steps - 1.0) / (steps - 1.0);
	// the last third of each line on screen (its lower half at two screen pixels a line, none at one)
	float gap = step(0.66, fract(UV.y / TEXTURE_PIXEL_SIZE.y));
	COLOR = vec4(v * (1.0 - scanlines * gap), c.a);
}
