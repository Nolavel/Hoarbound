"""Render review frames from the saved single-sheet Blender file."""
import bpy, os
from mathutils import Vector

out=os.environ.get('BEDROLL_OUT',os.path.dirname(bpy.data.filepath))
dest=os.path.join(out,'animation_frames')
os.makedirs(dest,exist_ok=True)
scene=bpy.context.scene
scene.render.engine='CYCLES'
scene.cycles.samples=6
scene.render.resolution_x=640
scene.render.resolution_y=480
cam=scene.camera
frames=(1,5,8,11,14,17,20,22,24,28,36,44,52,60,68,76,80,84,88,92)
start=Vector((1.35,-2.25,2.2));end=Vector((.9,-1.2,.75))
for i,frame in enumerate(frames):
    scene.frame_set(frame)
    t=max(0,min(1,(frame-28)/52))
    t=t*t*(3-2*t)
    cam.location=start.lerp(end,t)
    target=Vector((0,0,.10*t))
    cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.ortho_scale=2.3*(1-t)+.65*t
    scene.render.filepath=os.path.join(dest,f'{i:03d}.png')
    bpy.ops.render.render(write_still=True)
    print('FRAME',i,frame,flush=True)
os._exit(0)
