shader_type spatial;
render_mode unshaded, shadows_disabled, depth_draw_never;
#include "res://shaders/environment/stove/log_burn.gdshaderinc"
uniform float burn_progress=0.0;
uniform float animation_seconds=0.0;
uniform float root_x=0.0;
varying vec3 local_p;
void vertex(){
 float t=burn_progress*10.0+animation_seconds;
 float strength=flame_at(vec3(root_x,0.68,0.18),burn_progress);
 VERTEX.y=(VERTEX.y+0.64)*strength;
 VERTEX.x+=sin(VERTEX.y*5.0-t*4.3+root_x*3.0)*0.10*VERTEX.y;
 VERTEX.z+=sin(VERTEX.y*6.0-t*3.1)*0.075*VERTEX.y;
 local_p=VERTEX;
}
void fragment(){
 float t=burn_progress*10.0+animation_seconds;
 float h=local_p.y/1.28;
 float strength=flame_at(vec3(root_x,0.68,0.18),burn_progress);
 float fold=0.5+0.5*sin(local_p.x*9.0+local_p.z*8.0-h*5.0+t*4.0);
 float core=(1.0-h)*(0.45+0.55*fold);
 vec3 color=mix(vec3(1.0,0.31,0.045),vec3(1.0,0.72,0.27),smoothstep(0.1,0.6,core));
 color=mix(color,vec3(1.0,0.91,0.62),smoothstep(0.65,0.95,core));
 float edge=pow(abs(dot(normalize(NORMAL),normalize(VIEW))),0.55);
 ALBEDO=color;
 EMISSION=color*0.7;
 ALPHA=strength*edge*(0.45+0.2*fold)*(1.0-smoothstep(0.6,1.0,h));
}
