// Shared surface arrival field: local ignition on the front/top of one log.
float arrival_at(vec3 w) {
 float theta=atan(w.z,w.y-0.45);
 float angular=atan(sin(theta-0.65),cos(theta-0.65));
 return 0.035+length(vec2(w.x+0.8,angular*0.70))*0.24;
}
float char_at(vec3 w,float p) {return smoothstep(arrival_at(w),arrival_at(w)+0.035,min(p,0.53));}
float flame_at(vec3 w,float p){
 float age=p-arrival_at(w);
 return smoothstep(0.0,0.055,age)*(1.0-smoothstep(0.26,0.51,age))*(1.0-smoothstep(0.69,0.84,p));
}
