shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled, cull_disabled;
#include "res://shaders/environment/stove/log_burn.gdshaderinc"
uniform float burn_progress : hint_range(0,1)=0.0;
varying vec3 wp;
varying vec3 object_normal;
vec2 hash2(vec2 p){return fract(sin(vec2(dot(p,vec2(127.1,311.7)),dot(p,vec2(269.5,183.3))))*43758.5453);}
void vertex(){wp=VERTEX+vec3(0.0,0.48,0.0);object_normal=NORMAL;}
void fragment(){
 float a=atan(wp.z,wp.y-0.48);
 float grain=sin(a*11.0+0.5*sin(wp.x*2.7+a*3.0));
 float furrow=1.0-smoothstep(0.03,0.17,abs(grain));
 float broad=smoothstep(-0.5,0.7,sin(a*4.0+wp.x*0.5));
 vec3 bark=mix(vec3(0.20,0.13,0.075),vec3(0.39,0.27,0.15),broad)*(1.0-0.28*furrow);
 float split=smoothstep(0.7,0.95,object_normal.y);
 vec3 wood=mix(bark,mix(vec3(0.42,0.27,0.12),vec3(0.62,0.43,0.23),broad)*(1.0-furrow*0.13),split);
 if(abs(object_normal.x)>0.75){
  vec2 end=vec2((wp.y-0.46)*1.1,wp.z+0.025);
  float ring=sin(length(end)*61.0+0.35*sin(atan(end.y,end.x)*3.0));
  float rings=1.0-smoothstep(0.1,0.42,abs(ring));
  float radial=1.0-smoothstep(0.005,0.016,abs(end.y+0.3*end.x));
  wood=mix(vec3(0.54,0.36,0.18),vec3(0.30,0.18,0.075),rings*0.38+radial*0.4);
 }
 float burned=char_at(wp,burn_progress);
 // Sparse irregular charcoal plates, attached to the surface (no screen noise).
 vec2 q=vec2(wp.x*3.3,a*1.8);
 vec2 cell=floor(q),f=fract(q);
 float near1=10.0,near2=10.0;
 for(int y=-1;y<=1;y++){for(int x=-1;x<=1;x++){
  vec2 g=vec2(float(x),float(y));vec2 d=g+0.18+0.64*hash2(cell+g)-f;
  float dd=dot(d,d);if(dd<near1){near2=near1;near1=dd;}else{near2=min(near2,dd);}
 }}
 float crack=1.0-smoothstep(0.018,0.075,near2-near1);
 float age=burn_progress-arrival_at(wp);
 float heat=burned*smoothstep(0.02,0.14,age)*(1.0-smoothstep(0.63,1.0,burn_progress));
 heat*=0.7+0.3*sin(wp.x*3.8+a*2.3+burn_progress*8.0);
 vec3 coal=mix(vec3(0.07,0.063,0.058),vec3(0.15,0.13,0.105),broad)*(1.0-crack*0.4);
 ALBEDO=mix(wood,coal,burned);
 EMISSION=mix(vec3(0.65,0.045,0.003),vec3(1.0,0.30,0.025),heat)*crack*heat*(0.35+0.65*smoothstep(-0.6,0.7,sin(wp.x*2.1+a*1.7)))*0.65;
 // Sparse baked fill preserves the wood read in a cold firebox; no extra light source.
 EMISSION+=wood*0.04*(1.0-burned);
 ROUGHNESS=1.0;
}
