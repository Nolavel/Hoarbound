// Original implementation; scrolling/taper/color method informed by arlez80 (MIT).
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
#include "res://burn.gdshaderinc"
uniform float burn_progress : hint_range(0,1) = 0.0;
uniform float seed=0.0;
uniform vec3 root_position=vec3(0.0);
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void fragment(){
 float strength=flame_at(root_position,burn_progress);
 float t=burn_progress*10.0;
 float h=(1.0-UV.y)/max(0.01,strength);
 float n=noise(vec2(UV.x*3.0+seed,h*3.2-t*3.0));
 float sway=sin(h*5.0-t*6.0+seed)*0.11*h;
 float shape=(1.0-h)*0.47-abs(UV.x-0.5+sway)+(n-0.5)*0.15;
 float silhouette=smoothstep(-0.025,0.035,shape)*(1.0-smoothstep(0.85,1.0,h));
 float core=smoothstep(0.03,0.26,shape)*(1.0-h);
 vec3 col=mix(vec3(0.96,0.16,0.015),vec3(1.0,0.68,0.10),smoothstep(0.0,0.48,core));
 col=mix(col,vec3(1.0,0.90,0.40),smoothstep(0.4,0.8,core));
 ALBEDO=col; EMISSION=col*0.35;
 ALPHA=silhouette*smoothstep(0.0,0.05,strength)*0.96;
}
