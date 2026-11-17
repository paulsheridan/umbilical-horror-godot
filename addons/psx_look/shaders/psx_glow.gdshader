shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

#define PSX_GLOW
#define PSX_UNSHADED
#include "res://addons/psx_look/shaders/psx.gdshaderinc"
