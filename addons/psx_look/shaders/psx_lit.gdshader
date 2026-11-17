shader_type spatial;
// UMBILICAL deviation: per-pixel light falloff so the drone flashlight is a
// real beam on large CSG walls. The PS1 read still comes from vertex snap,
// affine mapping, nearest filtering, dither and fog.
render_mode specular_disabled;

#include "res://addons/psx_look/shaders/psx.gdshaderinc"
