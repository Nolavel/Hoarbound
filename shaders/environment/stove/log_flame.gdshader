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
 float u=(VERTEX.y+0.64)/1.28;
 VERTEX.xz*=0.95*(1.0-0.5*u);
 VERTEX.y=(VERTEX.y+0.64)*strength*1.65;
 VERTEX.x+=sin(VERTEX.y*5.0-t*4.3+root_x*3.0)*0.10*VERTEX.y;
 VERTEX.z+=sin(VERTEX.y*6.0-t*3.1)*0.075*VERTEX.y;
 local_p=VERTEX;
}
void fragment(){
 float t=burn_progress*10.0+animation_seconds;
 float strength=flame_at(vec3(root_x,0.68,0.18),burn_progress);
 float h=local_p.y/(2.112*max(strength,0.001));
 float fold=0.5+0.5*sin(local_p.x*9.0+local_p.z*8.0-h*3.0+t*4.0+root_x*3.7);
 float core=(1.0-h)*(0.45+0.55*fold);
 vec3 color=mix(vec3(1.0,0.20,0.025),vec3(1.0,0.55,0.12),smoothstep(0.1,0.6,core));
 color=mix(color,vec3(1.0,0.82,0.4),smoothstep(0.8,0.98,core));
 float edge=pow(abs(dot(normalize(NORMAL),normalize(VIEW))),0.35);
 ALBEDO=color*0.8;
 EMISSION=color*0.35;
 float tongues=mix(1.0,smoothstep(0.1,0.65,fold+(1.0-h)*0.4),smoothstep(0.45,0.85,h));
 ALPHA=strength*edge*(0.76+0.14*fold)*tongues*(1.0-smoothstep(0.45,1.0,h));
}
