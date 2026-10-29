"""Copy Henry's right hand, lightly close the fingers, and discard the rest.

Produces a static Blender reference only. Never writes the character GLB.
"""
import json
import math
from pathlib import Path
import bpy
import bmesh
from mathutils import Matrix, Quaternion, Vector

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/items/searchlight/source/candidate_v2'
SOURCE=ROOT/'assets/characters/henry/henry_outfit.glb'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
rig.animation_data_clear()
for pb in rig.pose.bones:
    pb.matrix_basis=Matrix.Identity(4)
# Close the existing rig's fingers statically around a transverse handle.
angles=[22.0,45.0,20.0]
for finger in ['index','middle','ring','pinky']:
    for joint,angle in enumerate(angles,1):
        pb=rig.pose.bones.get(f'{finger}_{joint:02}_r')
        if pb:
            local_axis=pb.bone.matrix_local.to_3x3().inverted() @ Vector((0,1,0))
            pb.rotation_mode='QUATERNION'
            pb.rotation_quaternion=Quaternion(local_axis.normalized(),-math.radians(angle))
for joint,angle in [(2,0),(3,0)]:
    pb=rig.pose.bones.get(f'thumb_{joint:02}_r')
    if pb:
        axis=pb.bone.matrix_local.to_3x3().inverted() @ Vector((0,1,0))
        pb.rotation_mode='QUATERNION';pb.rotation_quaternion=Quaternion(axis.normalized(),-math.radians(angle))
bpy.context.view_layer.update()
wrist=rig.matrix_world @ rig.pose.bones['hand_r'].head
bone_points={n:list(rig.matrix_world @ rig.pose.bones[n].head-wrist) for n in ['hand_r','middle_01_r','middle_02_r','middle_03_r','middle_04_leaf_r','thumb_03_r']}
created=[]
for source_name,name in [('Skin_Gloves','HenryRightHandBare')]:
    src=bpy.data.objects[source_name]
    groups={g.index for g in src.vertex_groups if g.name=='hand_r' or (g.name.endswith('_r') and g.name.startswith(('thumb_','index_','middle_','ring_','pinky_')))}
    keep={v.index for v in src.data.vertices if sum(g.weight for g in v.groups if g.group in groups)>.45 and (src.matrix_world @ v.co).x < wrist.x+.008}
    eval_ob=src.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=eval_ob.to_mesh()
    faces=[p for p in mesh.polygons if all(v in keep for v in p.vertices)]
    indices=sorted({v for p in faces for v in p.vertices});lookup={v:i for i,v in enumerate(indices)}
    new=bpy.data.meshes.new(name)
    new.from_pydata([src.matrix_world @ mesh.vertices[i].co-wrist for i in indices],[],[[lookup[v] for v in p.vertices] for p in faces])
    for mat in src.data.materials: new.materials.append(mat)
    for face,old in zip(new.polygons,faces): face.material_index=old.material_index
    eval_ob.to_mesh_clear()
    bm=bmesh.new();bm.from_mesh(new);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=0.00001);bmesh.ops.holes_fill(bm,edges=[e for e in bm.edges if e.is_boundary and all(v.co.x>-.03 for v in e.verts)],sides=0);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(new);bm.free()
    ob=bpy.data.objects.new(name,new);bpy.context.collection.objects.link(ob);created.append(ob)
# Only the copied right hand remains; no body, left hand, armature or animation.
for ob in list(bpy.data.objects):
    if ob not in created: bpy.data.objects.remove(ob,do_unlink=True)
created[0].hide_render=False;created[0].hide_set(False)
bpy.context.scene.unit_settings.system='METRIC';bpy.context.scene.unit_settings.scale_length=1
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'henry_right_hand.blend'))
report={'bone_points':bone_points,'source':str(SOURCE.relative_to(ROOT)),'side':'right','finger_curl_degrees':angles,'scale_preserved':True,'meshes':{ob.name:{'vertices':len(ob.data.vertices),'dimensions_m':list(ob.dimensions)} for ob in created},'remaining_objects':[o.name for o in bpy.context.scene.objects]}
(OUT/'hand_reference.json').write_text(json.dumps(report,indent=2))
print('@@JSON@@'+json.dumps(report))
