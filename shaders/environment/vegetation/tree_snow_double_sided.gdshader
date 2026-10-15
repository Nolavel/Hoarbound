// Stylized environment surface for trees, with snow on branch tops (tree_snow.gdshaderinc).
shader_type spatial;
render_mode cull_disabled, diffuse_lambert;

#include "res://shaders/environment/vegetation/tree_snow.gdshaderinc"
#define HFN_FRAGMENT_EXTRA tree_snow_apply(ALBEDO, ROUGHNESS, NORMAL, VERTEX, INV_VIEW_MATRIX);
#include "res://shaders/environment/materials/stylized_environment_body.gdshaderinc"
