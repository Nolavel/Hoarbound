shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;
#include "res://burn.gdshaderinc"
uniform float burn_progress : hint_range(0,1) = 0.0;
varying vec3 local_p;
varying vec3 wp;
void vertex(){local_p=VERTEX;wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 float angle=atan(local_p.z,local_p.x);
 float bands=sin(angle*13.0+sin(local_p.y*2.4+angle*2.0)*0.48);
 float groove=1.0-smoothstep(0.04,0.16,abs(bands));
 float broad=0.5+0.5*sin(angle*5.0+local_p.y*0.9);
 vec3 wood=mix(vec3(0.17,0.065,0.025),vec3(0.39,0.21,0.085),smoothstep(0.25,0.75,broad));
 wood*=1.0-groove*0.33;
 // End grain: broad rings only on the flat cylinder caps.
 if(abs(local_p.y)>1.595){
  float ring=sin(length(local_p.xz)*55.0+sin(angle*3.0)*0.30);
  wood=mix(vec3(0.36,0.17,0.066),vec3(0.58,0.34,0.15),smoothstep(-0.4,0.4,ring));
 }
 float burned=char_at(wp,burn_progress);
 float crack_long=1.0-smoothstep(0.025,0.065,abs(sin(angle*9.0+0.38*sin(local_p.y*3.4))));
 float crack_cross=(1.0-smoothstep(0.025,0.065,abs(sin(local_p.y*8.0+sin(angle*4.0)*0.65))))*0.55;
 float crack=max(crack_long,crack_cross);
 vec3 coal=mix(vec3(0.10,0.083,0.078),vec3(0.16,0.13,0.115),broad);
 ALBEDO=mix(wood,coal,burned);
 float heat=burned*(1.0-smoothstep(0.62,1.0,burn_progress));
 heat*=0.65+0.35*sin(angle*3.0+burn_progress*35.0)*sin(local_p.y*4.0-burn_progress*24.0);
 EMISSION=mix(vec3(0.9,0.045,0.003),vec3(1.0,0.33,0.025),heat)*crack*heat*1.8;
 ROUGHNESS=1.0;
}
