import bpy, json, os
from mathutils import Vector

scene=bpy.context.scene
sheet=bpy.data.objects['Bedroll_Continuous_Sheet']
assert sheet.type=='MESH'
assert len([o for o in scene.objects if o.name.startswith('Bedroll_Continuous_Sheet')])==1
mesh=sheet.data
assert len(mesh.materials)==3 and all('core' not in material.name.lower() for material in mesh.materials)
assert not any('cap' in obj.name.lower() or 'plug' in obj.name.lower() for obj in scene.objects)
parent=list(range(len(mesh.vertices)))
def find(a):
    while parent[a]!=a:
        parent[a]=parent[parent[a]];a=parent[a]
    return a
for e in mesh.edges:
    a,b=e.vertices[:];parent[find(a)]=find(b)
components=len({find(i) for i in range(len(parent))})
assert components==1,components
out={'source_mesh':mesh.name,'vertices':len(mesh.vertices),'faces':len(mesh.polygons),'connected_components':components,'one_mesh_at_all_frames':True,'frames':{}}
top_vertices=[v for v in mesh.vertices if v.co.z>.005]
def top_at(x,y):
    return min(top_vertices,key=lambda v:(v.co.x-x)**2+(v.co.y-y)**2).co.z
dent_depth=top_at(-.30,.361)-top_at(-.1575,.361)
assert .0006<dent_depth<.003,dent_depth
out['pressure_hollow_depth_mm']=round(dent_depth*1000,2)
for frame in (1,12,22,24,26,52,76,80,86,92):
    scene.frame_set(frame)
    assert sheet.data is mesh, f'mesh datablock replaced at frame {frame}'
    deps=bpy.context.evaluated_depsgraph_get()
    evaluated=sheet.evaluated_get(deps).to_mesh()
    xyz=[sheet.matrix_world@v.co for v in evaluated.vertices]
    mins=[min(p[i] for p in xyz) for i in range(3)]
    maxs=[max(p[i] for p in xyz) for i in range(3)]
    out['frames'][str(frame)]={'bounds_min_m':mins,'bounds_max_m':maxs,'dimensions_m':[maxs[i]-mins[i] for i in range(3)],'vertices':len(evaluated.vertices),'visible':not sheet.hide_render}
    sheet.evaluated_get(deps).to_mesh_clear()
assert out['frames']['1']['vertices']==out['frames']['80']['vertices']==out['frames']['92']['vertices']
assert .73<out['frames']['1']['dimensions_m'][0]<.78
assert out['frames']['12']['dimensions_m'][2]>.20  # the right half is visibly lifting
assert .34<out['frames']['22']['dimensions_m'][0]<.40
assert out['frames']['22']['dimensions_m'][2]<.04  # laid on itself before rolling
assert .34<out['frames']['80']['dimensions_m'][0]<.40
assert .11<out['frames']['80']['dimensions_m'][2]<.16
assert .11<out['frames']['92']['dimensions_m'][2]<.16
assert .34<out['frames']['92']['dimensions_m'][0]<.40
packed=out['frames']['92']['dimensions_m']
assert abs(packed[0]-.40)<.012  # previous Godot cylinder was 40 cm along its axis
assert abs(max(packed[1],packed[2])-.124)<.015  # and 12.4 cm across
out['old_pack_proxy_difference_cm']={
    'width':round((packed[0]-.40)*100,2),
    'diameter':round((max(packed[1],packed[2])-.124)*100,2),
}
assert all(v['bounds_min_m'][2]>-.001 for v in out['frames'].values())
for name in ('bedroll_top_color.png','bedroll_bottom_color.png','bedroll_wear_mask.png','bedroll_indent_mask.png','bedroll_fiber_height.png','bedroll_split_mask.png'):
    image=bpy.data.images.get(name)
    assert image is not None and image.packed_file is not None,name
bands=[bpy.data.objects[f'Removable_Strap_{label}'] for label in ('Left','Right')]
scene.frame_set(80)
assert all(b.hide_render for b in bands)
assert sheet.data.shape_keys.key_blocks['Strap_Compression'].value==0
coords_80=[sheet.matrix_world@v.co for v in sheet.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh().vertices]
sheet.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh_clear()
scene.frame_set(92)
assert all(not b.hide_render for b in bands)
for band,expected_x in zip(bands,(-.11,.11)):
    assert abs(band.matrix_world.translation.x-expected_x)<.006,(band.name,band.matrix_world.translation.x)
    assert out['frames']['92']['bounds_min_m'][0]<band.matrix_world.translation.x<out['frames']['92']['bounds_max_m'][0]
assert sheet.data.shape_keys.key_blocks['Strap_Compression'].value==1
coords_92=[sheet.matrix_world@v.co for v in sheet.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh().vertices]
sheet.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh_clear()
base_key=sheet.data.shape_keys.key_blocks['Basis']
pressure_key=sheet.data.shape_keys.key_blocks['Strap_Compression']
pressure=[(pressure_key.data[i].co-base_key.data[i].co).length for i in range(len(mesh.vertices))]
max_press=max(pressure)
assert .008<max_press<.012,max_press
out['strap_compression_max_mm']=round(max_press*1000,2)
for side in (-1,1):
    local=[pressure[i] for i,v in enumerate(mesh.vertices)
           if abs((v.co.x if v.co.x<0 else -v.co.x)+.75/4-side*.11)<.008]
    assert local and max(local)>.008,(side,max(local,default=0))
    out[f'strap_{"left" if side<0 else "right"}_dent_mm']=round(max(local)*1000,2)
middle=max(pressure[i] for i,v in enumerate(mesh.vertices)
           if abs((v.co.x if v.co.x<0 else -v.co.x)+.75/4)<.01)
assert middle<.001,middle
out['unstrapped_middle_shift_mm']=round(middle*1000,2)
# The first top vertex on the centre seam is the innermost turn. A visibly
# hollow roll from the old 27 mm core fails this check.
core_z=(.003**2+.006*1.9/3.141592653589793)**.5+.70*(2*.0065-.0025)
core_radius=min((p.y**2+(p.z-core_z)**2)**.5 for p in coords_80)
assert core_radius<.012,core_radius
out['inner_core_radius_mm']=round(core_radius*1000,2)
for side in ('Left','Right'):
    assert all(bpy.data.objects.get(f'Ladderlock_{side}_{j}') for j in range(6))
print('BEDROLL_QA',json.dumps(out),flush=True)
os._exit(0)
