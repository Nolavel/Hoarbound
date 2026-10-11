// Double-sided stylized environment surface for static world geometry: no camera fade.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert;

#define HFN_STATIC_WORLD
#include "res://shaders/environment/materials/stylized_environment_body.gdshaderinc"
