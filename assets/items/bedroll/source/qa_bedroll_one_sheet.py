import bpy, json, os
from mathutils import Vector

scene=bpy.context.scene
sheet=bpy.data.objects['Bedroll_Continuous_Sheet']
assert sheet.type=='MESH'
assert len([o for o in scene.objects if o.name.startswith('Bedroll_Continuous_Sheet')])==1
mesh=sheet.data
parent=list(range(len(mesh.vertices)))
def find(a):
    while parent[a]!=a:
        parent[a]=parent[parent[a]];a=parent[a]
    return a
for e in mesh.edges:
    a,b=e.vertices[:];parent[find(a)]=find(b)
components=len({find(i) for i in range(len(parent))})
assert components==1,components
out={'vertices':len(mesh.vertices),'faces':len(mesh.polygons),'connected_components':components,'one_mesh_at_all_frames':True,'frames':{}}
for frame in (1,20,26,36,42,54,58,61,64,70,76):
    scene.frame_set(frame)
    deps=bpy.context.evaluated_depsgraph_get()
    evaluated=sheet.evaluated_get(deps).to_mesh()
    xyz=[sheet.matrix_world@v.co for v in evaluated.vertices]
    mins=[min(p[i] for p in xyz) for i in range(3)]
    maxs=[max(p[i] for p in xyz) for i in range(3)]
    out['frames'][str(frame)]={'bounds_min_m':mins,'bounds_max_m':maxs,'dimensions_m':[maxs[i]-mins[i] for i in range(3)],'vertices':len(evaluated.vertices),'visible':not sheet.hide_render}
    sheet.evaluated_get(deps).to_mesh_clear()
assert out['frames']['1']['vertices']==out['frames']['64']['vertices']
assert .73<out['frames']['1']['dimensions_m'][0]<.78
assert .73<out['frames']['26']['dimensions_m'][0]<.78
assert .73<out['frames']['64']['dimensions_m'][0]<.78
assert .30<out['frames']['64']['dimensions_m'][2]<.40
assert out['frames']['61']['dimensions_m'][2]>.29
assert out['frames']['61']['dimensions_m'][1]>.16
assert all(v['bounds_min_m'][2]>-.001 for v in out['frames'].values())
prev_height=0.0
for frame in range(9,65):
    scene.frame_set(frame)
    deps=bpy.context.evaluated_depsgraph_get()
    evaluated=sheet.evaluated_get(deps).to_mesh()
    zz=[(sheet.matrix_world@v.co).z for v in evaluated.vertices]
    height=max(zz)-min(zz)
    sheet.evaluated_get(deps).to_mesh_clear()
    assert height>=prev_height-.01,(frame,prev_height,height)
    prev_height=height
for name in ('bedroll_top_color.png','bedroll_bottom_color.png','bedroll_wear_mask.png','bedroll_split_mask.png'):
    image=bpy.data.images.get(name)
    assert image is not None and image.packed_file is not None,name
bands=[bpy.data.objects[f'Removable_Strap_{label}'] for label in ('Left','Right')]
scene.frame_set(64)
assert all(b.hide_render for b in bands)
assert sheet.data.shape_keys.key_blocks['Strap_Compression'].value==0
coords_64=[sheet.matrix_world@v.co for v in sheet.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh().vertices]
sheet.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh_clear()
scene.frame_set(76)
assert all(not b.hide_render for b in bands)
assert sheet.data.shape_keys.key_blocks['Strap_Compression'].value==1
coords_76=[sheet.matrix_world@v.co for v in sheet.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh().vertices]
sheet.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh_clear()
max_press=max((a-b).length for a,b in zip(coords_64,coords_76))
assert .006<max_press<.020,max_press
out['strap_compression_max_mm']=round(max_press*1000,2)
print('BEDROLL_QA',json.dumps(out),flush=True)
os._exit(0)
