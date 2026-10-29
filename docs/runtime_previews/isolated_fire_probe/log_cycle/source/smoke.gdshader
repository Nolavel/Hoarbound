shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
uniform float burn_progress : hint_range(0,1)=0.0;
void fragment(){
 float t=burn_progress*10.0;
 float h=1.0-UV.y;
 float center=0.30+0.19*h+0.035*sin(h*9.0-t*2.3);
 float w=0.035+0.08*h;
 float ribbon=exp(-pow((UV.x-center)/w,2.0)*2.0);
 float drift=0.55+0.45*sin(h*13.0-t*4.0);
 float ignition=smoothstep(0.015,0.07,burn_progress)*(1.0-smoothstep(0.16,0.34,burn_progress));
 float envelope=smoothstep(0.0,0.13,h)*(1.0-smoothstep(0.72,1.0,h));
 ALBEDO=vec3(0.42,0.44,0.47);
 ALPHA=ribbon*drift*envelope*ignition*0.10;
}
