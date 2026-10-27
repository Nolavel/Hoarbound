shader_type spatial;
render_mode unshaded, shadows_disabled, depth_draw_never;
uniform float burn_progress=0.0;
uniform float animation_seconds=0.0;
varying vec3 local_p;
void vertex(){
 float t=burn_progress*10.0+animation_seconds;
 local_p=VERTEX;
 VERTEX.x+=0.12*sin(VERTEX.y*4.0-t*1.6)*VERTEX.y;
}
void fragment(){
 float ignition=smoothstep(0.02,0.07,burn_progress)*(1.0-smoothstep(0.16,0.34,burn_progress));
 float edge=pow(abs(dot(normalize(NORMAL),normalize(VIEW))),1.2);
 float h=(local_p.y+1.0)*0.5;
 ALBEDO=vec3(0.42,0.43,0.44);
 ALPHA=ignition*edge*(1.0-smoothstep(0.3,1.0,h))*0.045;
}
