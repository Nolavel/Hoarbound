"""Bake approved NORTHBEAM Blender source and export a Godot 4 game GLB."""
import importlib,json,sys
from pathlib import Path
import bpy,bmesh
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'assets/items/searchlight/source/candidate_v2/searchlight_geometry_review.blend'
OUT=ROOT/'assets/items/searchlight'
EVIDENCE=ROOT/'docs/runtime_previews/key_west_727/searchlight/game_ready'
EVIDENCE.mkdir(parents=True,exist_ok=True)
skills=Path(sys.argv[sys.argv.index('--')+1:][1])/ 'skills'
for name in ['blender-retopology-uv','blender-texture-baking','blender-export-pipelines','blender-asset-qa','blender-game-optimization']:
 sys.path.insert(0,str(skills/name/'scripts'))
uv=importlib.import_module('uv_pack');bake=importlib.import_module('bake_maps')
qa=importlib.import_module('qa_check');stats=importlib.import_module('mesh_stats');export=importlib.import_module('export_asset')
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene=bpy.context.scene
for ob in list(bpy.data.objects):
 if ob.type not in ('MESH','EMPTY'):bpy.data.objects.remove(ob,do_unlink=True)
decals=[o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith('Marking_')]
parts=[o for o in bpy.data.objects if o.type=='MESH' and o.name!='ClearRecessedLens' and o not in decals]
lens=bpy.data.objects['ClearRecessedLens'];lens.name='Searchlight_Lens'
bpy.ops.object.select_all(action='DESELECT')
for o in parts:o.select_set(True)
bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();combined=bpy.context.object;combined.name='SearchlightAtlasSource'
(EVIDENCE/'uv.json').write_text(json.dumps(uv.run(objects=[combined.name],method='smart',seams_from_sharp=60,res=1024,margin_px=8),indent=2))
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=8
OUT_TEXTURES=OUT/'textures';OUT_TEXTURES.mkdir(exist_ok=True)
receipt=bake.run(low=combined.name,maps=['basecolor','roughness','metallic','ao','normal'],res=1024,samples=8,margin_px=8,out=str(OUT_TEXTURES),name='Searchlight',pack_orm=True,device='CPU')
(EVIDENCE/'bake.json').write_text(json.dumps(receipt,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'source/searchlight_baked.blend'))
mat=bpy.data.materials.new('M_SearchlightAtlas');bsdf=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED');nodes,links=mat.node_tree.nodes,mat.node_tree.links
for suffix,socket,color_space in [('BC','Base Color','sRGB'),('N','Normal','Non-Color'),('ORM','ORM','Non-Color')]:
 image=bpy.data.images.load(str(OUT_TEXTURES/('T_Searchlight_'+suffix+'.png')),check_existing=True);image.colorspace_settings.name=color_space;image.pack()
 n=nodes.new('ShaderNodeTexImage');n.image=image
 if suffix=='BC':links.new(n.outputs['Color'],bsdf.inputs['Base Color'])
 if suffix=='N':normal=nodes.new('ShaderNodeNormalMap');links.new(n.outputs['Color'],normal.inputs['Color']);links.new(normal.outputs[0],bsdf.inputs['Normal'])
 if suffix=='ORM':split=nodes.new('ShaderNodeSeparateColor');links.new(n.outputs['Color'],split.inputs[0]);links.new(split.outputs['Green'],bsdf.inputs['Roughness']);links.new(split.outputs['Blue'],bsdf.inputs['Metallic'])
combined.data.materials.clear();combined.data.materials.append(mat)
for face in combined.data.polygons:face.material_index=0
combined.name='Searchlight_Body'
for o in [combined,lens]+decals:
 bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.triangulate(bm,faces=bm.faces);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(o.data);bm.free()
markers=[o.name for o in bpy.data.objects if o.type=='EMPTY' and o.name in ('GripAnchor','OpticalCenter')]
if len(markers)!=2:raise RuntimeError('Missing grip or optical marker')
names=[combined.name,lens.name]+[o.name for o in decals]
(EVIDENCE/'model_qa.json').write_text(json.dumps(qa.run(objects=names,profile='game',eps=.00015,tol=.004),indent=2))
(EVIDENCE/'model_stats.json').write_text(json.dumps(stats.run(objects=names,budget='pc'),indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'source/searchlight.blend'))
result=export.run(preset='godot',objects=names+markers,out=str(OUT/'searchlight.glb'),no_anim=True,set=['export_tangents=True'])
(EVIDENCE/'export.json').write_text(json.dumps(result,indent=2))
print('@@JSON@@'+json.dumps({'asset':str(OUT/'searchlight.glb'),'export':result}),flush=True)
