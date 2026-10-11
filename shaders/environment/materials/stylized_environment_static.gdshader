// Stylized environment surface for static world geometry (generated chunks): no camera fade.
shader_type spatial;
render_mode diffuse_lambert;

#define HFN_STATIC_WORLD
#include "res://shaders/environment/materials/stylized_environment_body.gdshaderinc"
