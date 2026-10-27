shader_type spatial;
render_mode unshaded, shadows_disabled, depth_draw_never;
// Same tongue technique as log_flame: height-graded colour, view-facing edge, faded tip.
// Unit mesh with its base at y = 0; the node scale sets the real size.
uniform float strength = 1.0;
varying float h;
void vertex(){
 h = VERTEX.y;
 VERTEX.x += sin(h*4.0-TIME*9.0)*0.05*h*h;
 VERTEX.z += sin(h*5.0-TIME*7.0)*0.04*h*h;
}
void fragment(){
 float fold = 0.5+0.5*sin(h*9.0-TIME*12.0);
 float edge = pow(abs(dot(normalize(NORMAL),normalize(VIEW))),0.5);
 vec3 color = mix(vec3(0.22,0.42,1.0),vec3(1.0,0.45,0.08),smoothstep(0.05,0.24,h));
 color = mix(color,vec3(1.0,0.78,0.32),smoothstep(0.2,0.45,h)*(1.0-smoothstep(0.75,1.0,h)));
 color = mix(color,vec3(1.0,0.95,0.80),0.6*edge*smoothstep(0.15,0.35,h)*(1.0-smoothstep(0.5,0.8,h)));
 ALBEDO = color;
 ALPHA = strength*edge*mix(0.45,1.0,smoothstep(0.0,0.2,h))*(0.9+0.1*fold)*(1.0-smoothstep(0.6,1.0,h));
}
