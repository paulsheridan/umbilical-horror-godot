// The PS1 look shared by every psx_*.gdshader: vertices snapped to the screen's pixel grid,
// affine (not perspective-correct) texture mapping, nearest-filtered textures, vertex colours;
// billboards, flipbooks and waves. The including shader sets render_mode, and may #define
// PSX_CUTOUT, PSX_TRANSPARENT, PSX_CHROME, PSX_GLOW or PSX_UNSHADED. psx_features.gdshaderinc defines
// which of the depth-cue fog, the draw distance and the textures' colour depth are installed.

#include "res://addons/psx_look/shaders/psx_features.gdshaderinc"

uniform bool unlit = false;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable, hint_default_white;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
// UV units per second, for water, lava and conveyor belts.
uniform vec2 uv_scroll = vec2(0.0);
// Size of the grid vertices snap to, in pixels of the viewport drawing them. 0 turns it off.
uniform float snap_pixels : hint_range(0.0, 8.0) = 1.0;
// 1 is the PS1's warping affine mapping, 0 the modern perspective-correct one.
uniform float affine : hint_range(0.0, 1.0) = 1.0;
uniform bool vertex_colors = true;
// A three-point texture filter in place of nearest pixels.
uniform bool three_point = false;
// World- or object-space planar mapping, for CSG and other meshes whose
// built-in UVs are per-face rather than per-metre. UMBILICAL's palette is
// world-triplanar, so the converter turns this on from the source material.
uniform bool triplanar = false;
uniform bool triplanar_world = true;
uniform float triplanar_scale = 1.0;
uniform vec3 triplanar_offset = vec3(0.0);
// Turns the mesh to the camera about its origin: 1 all the way (glows, particles), 2 upright,
// turning about Y only (trees, enemies, pickups).
uniform int billboard : hint_range(0, 2) = 0;
// A flipbook: the texture is columns x rows frames, read left to right, top to bottom, at fps
// (0 holds `frame`).
uniform vec2 frames = vec2(1.0);
uniform float fps = 0.0;
uniform float frame = 0.0;
// Vertices ride a wave along their normals: water, flags, foliage. Height in metres, length in
// metres, speed in waves a second.
uniform float wave_height = 0.0;
uniform float wave_length = 3.0;
uniform float wave_speed = 0.5;
// Holds the texture's top edge (UV y 0) still and lets the wave grow toward the bottom: a banner
// on its pole, a curtain.
uniform bool wave_pinned = false;
#ifdef PSX_FOG
// The PS1's depth cue, worked out per vertex: from fog_begin metres to fog_end the colour blends
// to fog_color, in bands across big polygons. A fog_end no further than fog_begin turns it off.
// Glow takes none.
uniform vec4 fog_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float fog_begin = 0.0;
uniform float fog_end = 0.0;
varying float psx_fog;
#endif
#ifdef PSX_DRAW_DISTANCE
// A polygon with a vertex further than this from the camera, in metres, isn't drawn, so the
// level draws in polygon by polygon as you near it, as the PS1's did. 0 draws everything.
uniform float draw_distance : hint_range(0.0, 1000.0) = 0.0;
#endif
#ifdef PSX_TEXTURE_BITS
// Bits a channel the texture's colours keep: 5 is the PS1's 15-bit texels, 8 the texture as it is.
uniform int texture_bits : hint_range(1, 8) = 8;
#endif
#ifdef PSX_CUTOUT
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;
#endif
#ifdef PSX_CHROME
// A sphere map looked up by the view-space normal, per vertex as on the PS1.
uniform sampler2D reflection_texture : source_color, filter_nearest, hint_default_black;
uniform float reflection : hint_range(0.0, 1.0) = 0.7;
varying vec3 psx_env;
#endif
#ifdef PSX_GLOW
// Faces seen edge-on fade (per vertex), so a cone or a cylinder of glow reads as a beam of light.
uniform float edge_fade : hint_range(0.0, 8.0) = 1.0;
varying float psx_fade;
#endif

varying vec3 psx_uv;
varying vec3 psx_uv_x;
varying vec3 psx_uv_y;
varying vec3 psx_uv_z;
varying vec3 psx_tri_blend;

void vertex() {
	if (billboard > 0) {
		mat4 turn = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		if (billboard == 2) {
			turn = mat4(vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0), vec4(0.0, 1.0, 0.0, 0.0),
					vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0), MODEL_MATRIX[3]);
		}
		MODELVIEW_MATRIX = VIEW_MATRIX * turn * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
				vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
	if (wave_height != 0.0) {
		vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float phase = dot(w, vec3(0.8, 0.5, 0.6)) * TAU / max(wave_length, 0.01) + TIME * TAU * wave_speed;
		float lift = 0.65 * sin(phase) + 0.35 * sin(phase * 1.7 + w.x - w.z);
		VERTEX += NORMAL * wave_height * lift * (wave_pinned ? clamp(UV.y, 0.0, 1.0) : 1.0);
	}
	vec2 uv = UV * uv_scale + uv_offset + uv_scroll * TIME;
	vec3 seen = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 clip = PROJECTION_MATRIX * vec4(seen, 1.0);
	float w_affine = mix(1.0, clip.w, affine);
	if (triplanar) {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 p = triplanar_world ? wp : VERTEX;
		vec3 n = triplanar_world
				? normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz) : normalize(NORMAL);
		vec3 blend = pow(abs(n), vec3(4.0));
		blend /= max(blend.x + blend.y + blend.z, 1e-5);
		psx_tri_blend = blend;
		vec2 yz = p.zy * triplanar_scale + triplanar_offset.zy + uv_scroll * TIME;
		vec2 xz = p.xz * triplanar_scale + triplanar_offset.xz + uv_scroll * TIME;
		vec2 xy = p.xy * triplanar_scale + triplanar_offset.xy + uv_scroll * TIME;
		psx_uv_x = vec3(yz * w_affine, w_affine);
		psx_uv_y = vec3(xz * w_affine, w_affine);
		psx_uv_z = vec3(xy * w_affine, w_affine);
		uv = yz;
	}
	if (snap_pixels > 0.0 && clip.w > 0.0) {
		vec2 grid = VIEWPORT_SIZE * 0.5 / snap_pixels;
		clip.xy = round(clip.xy / clip.w * grid) / grid * clip.w;
	}
	POSITION = clip;
#ifdef PSX_DRAW_DISTANCE
	if (draw_distance > 0.0 && length(seen) > draw_distance) {
		POSITION = vec4(uintBitsToFloat(0x7fc00000u));  // NaN: the GPU drops the triangles it is in
	}
#endif
#ifdef PSX_FOG
	psx_fog = fog_end > fog_begin ? clamp((length(seen) - fog_begin) / (fog_end - fog_begin), 0.0, 1.0) : 0.0;
#endif
	psx_uv = vec3(uv * w_affine, w_affine);
#ifdef PSX_CHROME
	vec3 n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	psx_env = vec3((n.xy * vec2(0.5, -0.5) + 0.5) * w_affine, w_affine);
#endif
#ifdef PSX_GLOW
	vec3 view = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	psx_fade = pow(max(abs(dot(normalize(MODELVIEW_NORMAL_MATRIX * NORMAL), normalize(view))), 1e-4), edge_fade);
#endif
}

// Compatibility (OUTPUT_IS_SRGB) hands the shader its textures and source_color uniforms in sRGB and
// reads ALBEDO and EMISSION back as sRGB, where Forward+ works in linear throughout: the fragment
// turns them linear and back, or every mix and fade in it lands darker there.
vec3 psx_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

vec3 psx_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}

// Blends the three texels nearest uv, over the triangle of the texel square uv falls in.
vec4 psx_three_point(sampler2D tex, vec2 uv) {
	vec2 size = vec2(textureSize(tex, 0));
	vec2 p = uv * size - 0.5;
	vec2 f = fract(p);
	vec2 base = (floor(p) + 0.5) / size;
	vec4 a = texture(tex, base);
	vec4 b = texture(tex, base + vec2(1.0 / size.x, 0.0));
	vec4 c = texture(tex, base + vec2(0.0, 1.0 / size.y));
	vec4 d = texture(tex, base + 1.0 / size);
	if (f.x + f.y <= 1.0) {
		return a + f.x * (b - a) + f.y * (c - a);
	}
	return d + (1.0 - f.x) * (c - d) + (1.0 - f.y) * (b - d);
}

void fragment() {
	vec2 uv = psx_uv.xy / psx_uv.z;
	vec4 c;
	if (triplanar) {
		vec2 ux = psx_uv_x.xy / psx_uv_x.z;
		vec2 uy = psx_uv_y.xy / psx_uv_y.z;
		vec2 uz = psx_uv_z.xy / psx_uv_z.z;
		vec4 cx = three_point ? psx_three_point(albedo_texture, ux) : texture(albedo_texture, ux);
		vec4 cy = three_point ? psx_three_point(albedo_texture, uy) : texture(albedo_texture, uy);
		vec4 cz = three_point ? psx_three_point(albedo_texture, uz) : texture(albedo_texture, uz);
		c = cx * psx_tri_blend.x + cy * psx_tri_blend.y + cz * psx_tri_blend.z;
	} else {
		if (frames.x * frames.y > 1.0) {
			vec2 grid = max(floor(frames), vec2(1.0));
			float f = mod(floor(fps > 0.0 ? TIME * fps : frame), grid.x * grid.y);
			uv = (fract(uv) + vec2(mod(f, grid.x), floor(f / grid.x))) / grid;
		}
		c = three_point ? psx_three_point(albedo_texture, uv) : texture(albedo_texture, uv);
	}
	vec3 tint = OUTPUT_IS_SRGB ? psx_linear(albedo.rgb) : albedo.rgb;
	c.rgb = OUTPUT_IS_SRGB ? psx_linear(c.rgb) : c.rgb;
#ifdef PSX_TEXTURE_BITS
	if (texture_bits < 8) {  // in sRGB, where the texture's own colours were stored
		float levels = exp2(float(texture_bits)) - 1.0;
		c.rgb = psx_linear(round(clamp(psx_srgb(c.rgb), 0.0, 1.0) * levels) / levels);
	}
#endif
	c *= vec4(tint, albedo.a);
	if (vertex_colors) {
		c *= COLOR;
	}
	vec3 shine = vec3(0.0);
#ifdef PSX_CHROME
	// A mirror: the reflection, tinted by albedo, is not shaded by the lights; the rest is.
	shine = texture(reflection_texture, psx_env.xy / psx_env.z).rgb;
	shine = (OUTPUT_IS_SRGB ? psx_linear(shine) : shine) * tint * reflection;
	c.rgb *= 1.0 - reflection;
#endif
#ifdef PSX_UNSHADED
	// an unshaded render mode draws ALBEDO alone, and drops EMISSION
	ALBEDO = c.rgb + shine;
#else
	ALBEDO = unlit ? vec3(0.0) : c.rgb;
	EMISSION = (unlit ? c.rgb : vec3(0.0)) + shine;
#endif
#if defined(PSX_FOG) && !defined(PSX_GLOW)
#ifdef PSX_UNSHADED
	ALBEDO = mix(ALBEDO, OUTPUT_IS_SRGB ? psx_linear(fog_color.rgb) : fog_color.rgb, psx_fog);
#else
	// the light reaches what's left of the colour, and the fog is added after it
	ALBEDO *= 1.0 - psx_fog;
	EMISSION = mix(EMISSION, OUTPUT_IS_SRGB ? psx_linear(fog_color.rgb) : fog_color.rgb, psx_fog);
#endif
#endif
#ifdef PSX_GLOW
	ALPHA = c.a * psx_fade;
#endif
	if (OUTPUT_IS_SRGB) {
#ifdef PSX_GLOW
		// Compatibility adds glow to what's behind in sRGB, where Forward+ adds in linear: it adds
		// what Forward+ would over a mid-dark background (sRGB 0.3), not a whole sRGB colour
		ALBEDO = psx_srgb(ALBEDO + 0.0732) - 0.3;
#else
		ALBEDO = psx_srgb(ALBEDO);
#endif
		EMISSION = psx_srgb(EMISSION);
	}
#ifdef PSX_CUTOUT
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
#endif
#ifdef PSX_TRANSPARENT
	ALPHA = c.a;
#endif
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
