shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
#include "res://burn.gdshaderinc"
uniform float burn_progress : hint_range(0,1)=0.0;
uniform float layer=0.0;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void fragment(){
 float t=burn_progress*10.0;
 float x=(UV.x-0.5)*3.55;
 float h=1.0-UV.y;
 float bend=0.11*sin(h*5.0-t*3.6)+0.07*sin(h*9.0-t*5.1+layer*2.0);
 float rootx=x-bend*h;
 float strength=flame_at(vec3(rootx,0.68,0.18),burn_progress);
 float n=noise(vec2(rootx*2.7+layer*17.0,h*3.2-t*2.4));
 float n2=noise(vec2(rootx*5.1+9.0,h*5.0-t*4.1));
 float height=strength*(0.22+0.56*n+0.26*n2);
 float body=height-h;
 float edge=smoothstep(-1.52,-1.30,rootx)*(1.0-smoothstep(1.30,1.52,rootx));
 float filament=noise(vec2(rootx*5.7+0.4*sin(h*5.0-t*2.1),h*4.2-t*3.4));
 float alpha=smoothstep(-0.035,0.07,body)*smoothstep(0.0,0.045,h)*strength;
 // Most flame is translucent amber; only selected dense folds are pale yellow.
 float core=smoothstep(0.06,0.36,body)*(0.45+0.55*n2);
 vec3 color=mix(vec3(1.0,0.30,0.035),vec3(1.0,0.71,0.24),smoothstep(0.05,0.5,core));
 color=mix(color,vec3(1.0,0.93,0.66),smoothstep(0.48,0.85,core));
 ALBEDO=color;EMISSION=color*0.65;
 ALPHA=alpha*edge*(0.50+0.16*core)*(1.0-layer*0.52)*mix(1.0,smoothstep(0.22,0.57,filament),smoothstep(0.12,0.65,h)*0.85);
}
