"""Build the Northbeam searchlight in Blender 5.2+, with the Blender Agent Skills.

Run Blender in background with this script, then -- --skills <blender-skills repo>.
Produces editable source, baked GLB, QA receipts and four genuine Blender renders.
"""
import argparse
import importlib
import json
import math
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
ASSET = ROOT / 'assets/items/searchlight'
EVIDENCE = ROOT / 'docs/runtime_previews/key_west_727/searchlight'
PARTS = []


def activate(objects):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]


def material(name, colour, roughness, metallic=0.0, painted=False):
    mat = bpy.data.materials.new(name)
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value = (*colour, 1)
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = metallic
    if painted:
        nodes, links = mat.node_tree.nodes, mat.node_tree.links
        tex = nodes.new('ShaderNodeTexNoise')
        tex.inputs['Scale'].default_value = 38
        tex.inputs['Detail'].default_value = 1
        coord = nodes.new('ShaderNodeTexCoord')
        links.new(coord.outputs['Position'], tex.inputs['Vector']) if 'Position' in coord.outputs else links.new(coord.outputs['Object'], tex.inputs['Vector'])
        ramp = nodes.new('ShaderNodeValToRGB')
        stops = [(0.23,(0.075,0.07,0.06,1)), (0.32,(0.18,0.10,0.026,1)), (0.40,(*colour,1)), (0.65,(0.38,0.23,0.045,1)), (0.78,(0.42,0.37,0.28,1))]
        ramp.color_ramp.elements.remove(ramp.color_ramp.elements[1])
        for i,(pos,col) in enumerate(stops):
            el = ramp.color_ramp.elements[0] if i == 0 else ramp.color_ramp.elements.new(pos)
            el.position,el.color = pos,col
        ramp.color_ramp.interpolation = 'CONSTANT'
        links.new(tex.outputs['Fac'], ramp.inputs[0])
        links.new(ramp.outputs[0], bsdf.inputs['Base Color'])
    return mat


def finish(ob, name, mat, role='Body', bevel=0.0):
    ob.name = name
    activate([ob])
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if bevel:
        result = STACK.run(objects=[ob.name], preset='midpoly', width=bevel, segments=1, apply=True)
        if not result.get('ok', True):
            raise RuntimeError(result)
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    vg = ob.vertex_groups.new(name=role)
    vg.add(list(range(len(ob.data.vertices))), 1.0, 'REPLACE')
    PARTS.append(ob)
    return ob


def box(name, at, size, mat, role='Body', bevel=0.002, rotation=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=at)
    ob=bpy.context.object
    ob.scale=size
    if rotation:
        ob.rotation_euler=rotation
    return finish(ob,name,mat,role,bevel)


def ring(name, y, outer, inner, depth, mat, segments=40):
    verts=[]
    for yy,rr in [(y-depth/2,outer),(y+depth/2,outer),(y-depth/2,inner),(y+depth/2,inner)]:
        verts.extend([(math.cos(i*math.tau/segments)*rr, yy, .113+math.sin(i*math.tau/segments)*rr) for i in range(segments)])
    faces=[]
    for i in range(segments):
        j=(i+1)%segments
        faces.extend([(i,j,segments+j,segments+i),(2*segments+i,3*segments+i,3*segments+j,2*segments+j),(i,2*segments+i,2*segments+j,j),(segments+i,segments+j,3*segments+j,3*segments+i)])
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    ob=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(ob)
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(mesh);bm.free()
    return finish(ob,name,mat)


def cylinder(name, at, radius, depth, mat, vertices=12, axis='Y'):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=at)
    ob=bpy.context.object
    if axis=='Y': ob.rotation_euler.x=math.pi/2
    if axis=='X': ob.rotation_euler.y=math.pi/2
    return finish(ob,name,mat)


def separate_role(combined, role, atlas):
    mesh=combined.data.copy();bm=bmesh.new();bm.from_mesh(mesh)
    layer=bm.verts.layers.deform.active
    idx=combined.vertex_groups[role].index
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if v[layer].get(idx,0)<.5],context='VERTS')
    bm.to_mesh(mesh);bm.free();mesh.materials.clear();mesh.materials.append(atlas)
    for p in mesh.polygons: p.material_index=0
    ob=bpy.data.objects.new('Searchlight_'+role,mesh);bpy.context.collection.objects.link(ob);ob.matrix_world=combined.matrix_world.copy()
    return ob


def main():
    args=argparse.ArgumentParser();args.add_argument('--skills',required=True);args.add_argument('--finalize',action='store_true')
    cfg=args.parse_args(sys.argv[sys.argv.index('--')+1:])
    skills=Path(cfg.skills)/'skills'
    for name in ['blender-hardsurface-modeling','blender-retopology-uv','blender-texture-baking','blender-export-pipelines','blender-asset-qa','blender-game-optimization']:
        sys.path.insert(0,str(skills/name/'scripts'))
    global STACK
    STACK=importlib.import_module('apply_stack')
    uv=importlib.import_module('uv_pack');bake=importlib.import_module('bake_maps')
    export=importlib.import_module('export_asset');qa=importlib.import_module('qa_check');stats=importlib.import_module('mesh_stats')
    if cfg.finalize:
        bpy.ops.wm.open_mainfile(filepath=str(ASSET/'source/searchlight_baked.blend'))
        finalize(skills)
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
    paint=material('M_MustardPaint',(.28,.15,.025),.8,painted=True)
    rubber=material('M_Rubber',(.023,.027,.03),.9)
    inset=material('M_Inset',(.075,.08,.078),.82)
    red=material('M_ControlRed',(.40,.045,.026),.72)
    metal=material('M_Reflector',(.55,.51,.40),.38,1)
    worn=material('M_EdgeWear',(.31,.29,.25),.78)
    box('MainHousing',(0,-.006,.112),(.174,.258,.176),paint,bevel=.012)
    box('BatteryBlock',(0,-.125,.115),(.17,.055,.157),rubber,'Battery',.007)
    box('BatteryPlate',(0,-.157,.115),(.138,.009,.124),inset,'Battery',.003)
    for x in [-.08,.08]:
        for y in [-.125,.098]:
            box('CornerBumper',(x,y,.112),(.024,.040,.177),rubber,bevel=.004)
        box('SidePaintPanel',(x*1.103,-.005,.112),(.009,.158,.119),paint,bevel=.003)
    box('HandleRearStrut',(0,-.09,.211),(.032,.032,.106),paint,bevel=.004,rotation=(math.radians(-16),0,0))
    box('HandleFrontStrut',(0,.095,.211),(.032,.032,.106),paint,bevel=.004,rotation=(math.radians(16),0,0))
    box('CarryHandle',(0,0,.257),(.040,.204,.027),paint,bevel=.005)
    box('HandleGrip',(0,-.001,.258),(.044,.105,.031),rubber,bevel=.004)
    for y in [-.04,-.024,-.008,.008,.024,.04]:
        box('GripRib',(0,y,.275),(.041,.004,.003),inset,bevel=.001)
    box('SwitchSurround',(0,-.075,.278),(.043,.043,.009),rubber,bevel=.003)
    box('PowerButton',(0,-.075,.286),(.030,.028,.01),red,'Button',.003)
    for x in [-.089,.089]:
        for z in [.07,.085,.10,.115,.13]:
            box('CoolingVent',(x,-.086,z),(.006,.035,.006),rubber,bevel=.001)
        box('BatteryLatch',(x,-.126,.11),(.012,.033,.045),red,'Battery',.002)
        for y in [-.062,.062]:
            for z in [.062,.161]:
                cylinder('PanelFastener',(x*1.04,y,z),.004,.005,worn,8,'X')
    ring('OpticHousing',.143,.111,.082,.042,paint)
    ring('LensGasket',.166,.108,.086,.013,rubber)
    ring('ReflectorBezel',.172,.086,.077,.009,metal)
    for i in range(12):
        a=i*math.tau/12
        ob=box('RimImpactGuard',(math.cos(a)*.105,.153,.113+math.sin(a)*.105),(.029,.055,.032),rubber,bevel=.003,rotation=(0,-a,0))
    reflector=ring('ReflectorCup',.151,.078,.018,.04,metal)
    # The back of the reflector is narrow, the front wide: an actual recessed dish.
    for v in reflector.data.vertices:
        radius=math.hypot(v.co.x,v.co.z-.113)
        back=v.co.y<.151
        v.co.y=(.172 if radius>.05 else .132)-(.002 if back else 0)
    reflector.data.update()
    cylinder('LEDModule',(0,.176,.113),.018,.006,worn,24)
    box('BatteryChargePanel',(.096,-.028,.115),(.008,.054,.025),rubber,bevel=.002)
    for y in [-.047,-.035,-.023,-.011]:
        box('ChargeWindow',(.101,y,.115),(.003,.005,.012),worn,bevel=.0008)
    # Mount and reflector are +Y in Blender, which exports to Godot -Z.
    meshes=list(PARTS);activate(meshes);bpy.ops.object.join();combined=bpy.context.object;combined.name='SearchlightAtlasSource'
    result=uv.run(objects=[combined.name],method='smart',seams_from_sharp=60,res=1024,margin_px=8)
    (EVIDENCE/'uv.json').write_text(json.dumps(result,indent=2))
    scene.render.engine='CYCLES';scene.cycles.samples=16
    result=bake.run(low=combined.name,maps=['basecolor','roughness','metallic','ao','normal'],res=1024,samples=16,margin_px=8,out=str(ASSET/'textures'),name='Searchlight',pack_orm=True,device='CPU')
    (EVIDENCE/'bake.json').write_text(json.dumps(result,indent=2))
    print('BAKE_RECEIPT',json.dumps(result),flush=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(ASSET/'source/searchlight_baked.blend'))
    finalize(skills)


def finalize(skills):
    combined=bpy.data.objects['SearchlightAtlasSource']
    atlas=material('M_SearchlightAtlas',(1,1,1),.8)
    nodes,links=atlas.node_tree.nodes,atlas.node_tree.links
    bsdf=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
    def texture(suffix, space):
        image=bpy.data.images.load(str(ASSET/'textures'/('T_Searchlight_'+suffix+'.png')),check_existing=True)
        image.colorspace_settings.name=space
        node=nodes.new('ShaderNodeTexImage');node.image=image
        return node
    bc=texture('BC','sRGB');links.new(bc.outputs['Color'],bsdf.inputs['Base Color'])
    orm=texture('ORM','Non-Color');split=nodes.new('ShaderNodeSeparateColor');links.new(orm.outputs['Color'],split.inputs[0])
    links.new(split.outputs['Green'],bsdf.inputs['Roughness']);links.new(split.outputs['Blue'],bsdf.inputs['Metallic'])
    normal=texture('N','Non-Color');nmap=nodes.new('ShaderNodeNormalMap');links.new(normal.outputs['Color'],nmap.inputs['Color']);links.new(nmap.outputs['Normal'],bsdf.inputs['Normal'])
    game=[separate_role(combined,role,atlas) for role in ['Body','Battery','Button']]
    bpy.data.objects.remove(combined,do_unlink=True)
    glass=material('M_SearchlightLens',(.88,.83,.65),.08)
    bsdf=next(n for n in glass.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    bsdf.inputs['Transmission Weight'].default_value=.95
    lens=cylinder('Searchlight_Lens',(0,.1775,.113),.079,.002,glass,40)
    # Native lens shading is controlled by the held prop, not by a second lamp.
    activate([lens]);importlib.import_module('uv_pack').run(objects=[lens.name],method='smart',res=256,margin_px=4)
    game.append(lens)
    for ob in game:
        bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.triangulate(bm,faces=bm.faces);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(ob.data);bm.free()
    shift=-min((ob.matrix_world @ Vector(c)).z for ob in game for c in ob.bound_box)
    for ob in game:
        ob.location.z+=shift
    for name,at in [('GripAnchor',(0,0,.258)),('OpticalCenter',(0,.179,.113)),('RestAnchor',(0,0,0))]:
        ob=bpy.data.objects.new(name,None);ob.location=Vector(at)+Vector((0,0,shift));bpy.context.collection.objects.link(ob)
    names=[o.name for o in game]
    result=importlib.import_module('qa_check').run(objects=names,profile='game',eps=.0002,tol=.004)
    (EVIDENCE/'model_qa.json').write_text(json.dumps(result,indent=2))
    info=importlib.import_module('mesh_stats').run(objects=names,budget='web')
    (EVIDENCE/'model_stats.json').write_text(json.dumps(info,indent=2))
    # Source textures are packed; the game GLB embeds its own exported texture bytes.
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(ASSET/'source/searchlight.blend'))
    result=importlib.import_module('export_asset').run(preset='godot',objects=names+['GripAnchor','OpticalCenter','RestAnchor'],out=str(ASSET/'searchlight.glb'),no_anim=True,set=['export_tangents=True'])
    (EVIDENCE/'export.json').write_text(json.dumps(result,indent=2))
    review=importlib.import_module('review_shots')
    for mode in ['material','wire']:
        receipt=review.run(objects=names,out=str(EVIDENCE/('qa_'+mode+'.png')),mode=mode,res=640)
        (EVIDENCE/('review_'+mode+'.json')).write_text(json.dumps(receipt,indent=2))
    render_model(game)
    print('@@JSON@@'+json.dumps({'ok':True,'asset':str(ASSET/'searchlight.glb'),'qa':str(EVIDENCE/'model_qa.json'),'stats':info}),flush=True)


def render_model(game):
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=24;scene.cycles.use_denoising=True
    scene.render.resolution_x=768;scene.render.resolution_y=768;scene.render.resolution_percentage=100
    scene.world=bpy.data.worlds.new('ReviewWorld');scene.world.use_nodes=True
    next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND').inputs['Color'].default_value=(.04,.055,.075,1)
    scene.view_settings.view_transform='AgX';scene.view_settings.exposure=-.5
    def light(name,at,power,size,colour):
        data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=colour
        ob=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(ob);ob.location=at;ob.rotation_euler=(Vector((0,0,.13))-ob.location).to_track_quat('-Z','Y').to_euler()
    light('Key',(.4,.4,.7),45,.5,(1,.83,.62));light('ColdFill',(-.45,.1,.4),18,.4,(.55,.70,1));light('Rim',(.2,-.5,.55),35,.35,(1,.70,.38))
    camera=bpy.data.objects.new('ReviewCamera',bpy.data.cameras.new('ReviewCamera'));bpy.context.collection.objects.link(camera);scene.camera=camera;camera.data.type='ORTHO';camera.data.ortho_scale=.51
    for name,at in [('front',(.46,.65,.40)),('rear',(-.48,-.64,.40)),('side',(.8,-.08,.29)),('top',(.28,.45,.9))]:
        camera.location=at;camera.rotation_euler=(Vector((0,.0,.142))-camera.location).to_track_quat('-Z','Y').to_euler();scene.render.filepath=str(EVIDENCE/('blender_'+name+'.png'));bpy.ops.render.render(write_still=True)


if __name__=='__main__':
    main()
