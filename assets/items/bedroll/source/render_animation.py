"""Render a lightweight MP4 review sequence from bedroll_candidate.blend."""
import bpy
import math
import os
from mathutils import Vector

out=os.environ.get("BEDROLL_OUT",os.path.dirname(bpy.data.filepath))
frames_dir=os.path.join(out,"animation_frames")
os.makedirs(frames_dir,exist_ok=True)
scene=bpy.context.scene
cam=scene.camera
scene.render.resolution_x=640
scene.render.resolution_y=480
scene.render.resolution_percentage=100
scene.cycles.samples=5
scene.cycles.use_denoising=True

frames=(1,5,9,14,18,22,27,32,37,42,47,51,53,54,56)
start=Vector((1.35,-2.2,2.45))
end=Vector((1.15,-1.55,1.05))
start_target=Vector((0,0,0))
end_target=Vector((0,0,.13))
for i,frame in enumerate(frames):
    scene.frame_set(frame)
    t=max(0,min(1,(frame-18)/38))
    t=t*t*(3-2*t)
    cam.location=start.lerp(end,t)
    target=start_target.lerp(end_target,t)
    cam.rotation_euler=(target-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.ortho_scale=2.35*(1-t)+.82*t
    scene.render.filepath=os.path.join(frames_dir,f"frame_{i:02d}.png")
    bpy.ops.render.render(write_still=True)
    print("ANIM_FRAME",frame,scene.render.filepath,flush=True)
os._exit(0)
