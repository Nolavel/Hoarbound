"""Blender-only geometry review of the Northbeam searchlight, Blender 5.2+.

Run with -- --skills <blender-skills repo>. The rejected v1 is archived under
assets/items/searchlight/source/intermediate_v1. This stage writes candidate_v2
only; final game baking, GLB replacement and Godot integration await approval.
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
ASSET = ROOT / 'assets/items/searchlight/source/candidate_v2'
EVIDENCE = ROOT / 'docs/runtime_previews/key_west_727/searchlight/candidate_v2'
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
        result = STACK.run(objects=[ob.name], preset='midpoly', width=min(bevel,min(ob.dimensions)*.2), segments=2, apply=True)
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



def lathe(name, profile, mat, segments=48, centre_z=.115):
    verts=[(r*math.cos(i*math.tau/segments),y,centre_z+r*math.sin(i*math.tau/segments)) for r,y in profile for i in range(segments)]
    faces=[]
    for j in range(len(profile)):
        k=(j+1)%len(profile)
        for i in range(segments):
            n=(i+1)%segments
            faces.append((j*segments+i,j*segments+n,k*segments+n,k*segments+i))
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    ob=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(ob)
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(mesh);bm.free()
    for face in mesh.polygons:face.use_smooth=True
    return finish(ob,name,mat)


def handle_sweep(mat):
    path=[(-.161,.168),(-.154,.200),(-.133,.230),(-.116,.238),(.060,.238),(.079,.230),(.100,.202),(.107,.168)]
    # Chamfered 22 x 16 mm section; the winter glove has a 65 mm-high opening.
    cross=[(-.008,-.008),(.008,-.008),(.011,-.005),(.011,.005),(.008,.008),(-.008,.008),(-.011,.005),(-.011,-.005)]
    vertices=[]
    for i,(y,z) in enumerate(path):
        before=Vector(path[max(0,i-1)]);after=Vector(path[min(len(path)-1,i+1)])
        tangent=(after-before).normalized();normal=Vector((-tangent.y,tangent.x))
        for x,d in cross:vertices.append((x,y+normal.x*d,z+normal.y*d))
    faces=[]
    for i in range(len(path)-1):
        for j in range(8):faces.append((i*8+j,i*8+(j+1)%8,(i+1)*8+(j+1)%8,(i+1)*8+j))
    faces += [tuple(range(7,-1,-1)),tuple((len(path)-1)*8+j for j in range(8))]
    mesh=bpy.data.meshes.new('ErgonomicHandle');mesh.from_pydata(vertices,[],faces);mesh.update()
    ob=bpy.data.objects.new('ErgonomicHandle',mesh);bpy.context.collection.objects.link(ob)
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(mesh);bm.free()
    return finish(ob,'ErgonomicHandle',mat)


def bumper_segment(name,angle,mat):
    count=5;vertices=[]
    for y,r in [(.179,.108),(.194,.108),(.179,.1135),(.194,.1135)]:
        for i in range(count):
            a=angle+math.radians(-7+14*i/(count-1));vertices.append((r*math.cos(a),y,.115+r*math.sin(a)))
    faces=[]
    for i in range(count-1):
        j=i+1
        faces += [(i,j,count+j,count+i),(2*count+i,3*count+i,3*count+j,2*count+j),(i,2*count+i,2*count+j,j),(count+i,count+j,3*count+j,3*count+i)]
    faces += [(0,count,3*count,2*count),(count-1,3*count-1,4*count-1,2*count-1)]
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(vertices,[],faces);mesh.update()
    ob=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(ob)
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(mesh);bm.free()
    return finish(ob,name,mat)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--skills',required=True);parser.add_argument('--grip-only',action='store_true');args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    skills=Path(args.skills)/'skills'
    for name in ['blender-hardsurface-modeling','blender-retopology-uv','blender-asset-qa','blender-game-optimization']:
        sys.path.insert(0,str(skills/name/'scripts'))
    global STACK
    STACK=importlib.import_module('apply_stack')
    if args.grip_only:
        bpy.ops.wm.open_mainfile(filepath=str(ASSET/'searchlight_geometry_review.blend'))
        render_review(json.loads((EVIDENCE/'geometry_review.json').read_text()).get('ground_shift_m',0.0),grip_only=True)
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
    paint=material('M_Mustard',(0.18,.095,.018),.72,painted=True)
    rubber=material('M_Rubber',(.012,.016,.019),.84)
    inset=material('M_Battery',(.035,.041,.045),.78)
    red=material('M_Switch',(.24,.027,.017),.66)
    metal=material('M_Bezel',(.32,.35,.38),.35,1)
    reflector=material('M_Reflector',(.83,.85,.87),.13,1)
    chip=material('M_LED_Die',(.53,.40,.12),.38)
    ceramic=material('M_LED_Ceramic',(.72,.70,.60),.52)
    box('MainHousing',(0,-.054,.090),(.152,.282,.144),paint,bevel=.012)
    box('BatteryBlock',(0,-.193,.092),(.150,.060,.142),rubber,'Battery',.008)
    box('BatteryRearPlate',(0,-.225,.091),(.133,.008,.124),inset,'Battery',.005)
    for x in [-.075,.075]:
        box('SidePanel',(x,-.059,.090),(.009,.186,.112),paint,bevel=.004)
        for y in [-.172,.061]:box('BodyEdgeBumper',(x,y,.088),(.014,.025,.142),rubber,bevel=.003)
        box('Latch',(x*1.073,-.184,.105),(.012,.025,.036),red,'Battery',.002)
        for z in [.063,.075,.087,.099,.111]:box('CoolingSlot',(x*1.07,-.120,z),(.003,.032,.004),rubber,bevel=.0006)
        for y in [-.130,.008]:
            for z in [.052,.132]:cylinder('PanelScrew',(x*1.085,y,z),.003,.003,metal,8,'X')
    box('BatteryPortCover',(0,-.232,.087),(.045,.005,.040),rubber,'Battery',.003)
    handle_sweep(paint)
    box('GripRubber',(0,-.025,.238),(.026,.145,.020),rubber,bevel=.003)
    for y in [-.084,-.064,-.044,-.024,-.004,.016,.036]:box('GripFineRib',(0,y,.250),(.023,.002,.0015),inset,bevel=.0004)
    box('SwitchSeat',(0,.071,.244),(.035,.032,.009),rubber,bevel=.003)
    box('PowerButton',(0,.071,.251),(.024,.021,.007),red,'Button',.002)
    # A tapered optical housing, not a cylinder filled by the body cube.
    lathe('OpticalHousing',[(.088,.080),(.096,.085),(.109,.153),(.110,.181),(.107,.185),(.101,.179),(.100,.155),(.087,.091)],paint)
    lathe('MetalFrontBezel',[(.108,.176),(.110,.181),(.110,.194),(.106,.200),(.098,.200),(.096,.196),(.096,.186),(.100,.180)],metal)
    lathe('GlassSeal',[(.0975,.188),(.099,.190),(.099,.197),(.095,.197),(.0948,.193),(.0948,.189)],rubber)
    for i in range(6):bumper_segment('SmallRimPad_%d'%i,i*math.tau/6, rubber)
    profile=[]
    for i in range(9):
        r=.009+(.094-.009)*i/8;profile.append((r,.102+.081*(r/.094)**2))
    profile += [(r,y-.0018) for r,y in reversed(profile)]
    lathe('DeepParabolicReflector',profile,reflector,48)
    cylinder('LEDHeatSlug',(0,.104,.115),.014,.009,metal,24)
    box('LEDSubstrate',(0,.111,.115),(.014,.003,.014),ceramic,bevel=.0008)
    box('LEDEmitter',(0,.113,.115),(.007,.0015,.007),chip,bevel=.0003)
    glass=material('M_ClearProtectiveGlass',(1,1,1),.025)
    shader=next(n for n in glass.node_tree.nodes if n.type=='BSDF_PRINCIPLED');shader.inputs['Transmission Weight'].default_value=1;shader.inputs['IOR'].default_value=1.46
    vertices=[(0,.196,.115),(0,.1938,.115)]
    for back in [False,True]:
        for row in range(1,5):
            r=.0948*row/4;y=.194+.002*(1-(r/.0948)**2)-(.0022 if back else 0)
            vertices += [(r*math.cos(i*math.tau/64),y,.115+r*math.sin(i*math.tau/64)) for i in range(64)]
    faces=[]
    for back in [False,True]:
        offset=2+(256 if back else 0);pole=1 if back else 0
        for i in range(64):
            j=(i+1)%64;faces.append((pole,offset+i,offset+j))
        for row in range(3):
            for i in range(64):
                j=(i+1)%64;a=offset+row*64;faces.append((a+i,a+64+i,a+64+j,a+j))
    for i in range(64):
        j=(i+1)%64;faces.append((194+i,194+j,450+j,450+i))
    mesh=bpy.data.meshes.new('ProtectiveGlass');mesh.from_pydata(vertices,[],faces);mesh.update()
    lens=bpy.data.objects.new('ClearRecessedLens',mesh);bpy.context.collection.objects.link(lens)
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(mesh);bm.free()
    for face in mesh.polygons:face.use_smooth=True
    finish(lens,'ClearRecessedLens',glass)
    # Shape and scale only; no beam, emitted glow or animation in this review.
    bpy.context.view_layer.update()
    shift=-min((ob.matrix_world @ Vector(c)).z for ob in PARTS for c in ob.bound_box)
    for ob in PARTS:ob.location.z+=shift
    for name,at in [('GripAnchor',(0,-.025,.238+shift)),('OpticalCenter',(0,.199,.115+shift))]:
        ob=bpy.data.objects.new(name,None);ob.location=at;bpy.context.collection.objects.link(ob)
    for ob in PARTS:
        bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.triangulate(bm,faces=bm.faces);bm.to_mesh(ob.data);bm.free()
    names=[o.name for o in PARTS]
    uv=importlib.import_module('uv_pack').run(objects=names,method='smart',res=1024,margin_px=8)
    (EVIDENCE/'uv_review.json').write_text(json.dumps(uv,indent=2))
    report=importlib.import_module('qa_check').run(objects=names,profile='game',eps=.00015,tol=.004)
    (EVIDENCE/'geometry_qa.json').write_text(json.dumps(report,indent=2))
    stats=importlib.import_module('mesh_stats').run(objects=names,budget='pc')
    (EVIDENCE/'model_stats.json').write_text(json.dumps(stats,indent=2))
    metrics={'ground_shift_m':shift,'handle_section_mm':[22,16],'rubber_grip_section_mm':[26,20],'clearance_above_case_mm':(.238-.010-.162)*1000,'reflector_depth_mm':81,'lens_diameter_mm':189.6,'rim_pad_radial_projection_mm':3.5,'hand_source':'henry_right_hand.blend','game_integration':'paused, geometry not approved'}
    (EVIDENCE/'geometry_review.json').write_text(json.dumps(metrics,indent=2))
    bpy.ops.wm.save_as_mainfile(filepath=str(ASSET/'searchlight_geometry_review.blend'))
    render_review(shift)
    print('@@JSON@@'+json.dumps({'qa':report.get('pass'),'stats':stats,'metrics':metrics}))


def render_review(shift,grip_only=False):
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=24;scene.cycles.use_denoising=True
    scene.cycles.max_bounces=12;scene.cycles.transmission_bounces=8
    scene.render.resolution_x=900;scene.render.resolution_y=720;scene.render.resolution_percentage=100
    scene.world=bpy.data.worlds.new('ReviewWorld');scene.world.use_nodes=True
    background=next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND');background.inputs['Color'].default_value=(.055,.065,.08,1);background.inputs['Strength'].default_value=.5
    scene.view_settings.view_transform='AgX';scene.view_settings.exposure=-1.1
    def light(name,at,power,size,colour,shape='DISK',size_y=None):
        data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape=shape;data.size=size;data.color=colour
        if size_y is not None:data.size_y=size_y
        ob=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(ob);ob.location=at;ob.rotation_euler=(Vector((0,-.03,.12))-ob.location).to_track_quat('-Z','Y').to_euler()
    light('Key',(-.40,.35,.70),35,.40,(1,.88,.70))
    light('SoftFill',(.5,-.1,.40),10,.45,(.68,.80,1))
    light('GlassReflectionStrip',(.35,.6,.3),13,.06,(1,.96,.86),'RECTANGLE',.45)
    light('RearEdge',(-.3,-.55,.45),25,.35,(1,.76,.50))
    camera=bpy.data.objects.new('ReviewCamera',bpy.data.cameras.new('ReviewCamera'));bpy.context.collection.objects.link(camera);scene.camera=camera;camera.data.type='ORTHO'
    views=[] if grip_only else [('front',(0,1,.139),(0,0,.127),.39),('side',(1,-.01,.145),(0,-.016,.127),.56),('perspective',(.58,.77,.42),(0,-.015,.128),.52),('optics',(.16,.8,.24),(0,.145,.115),.29)]
    for name,at,look,scale in views:
        camera.data.ortho_scale=scale;camera.location=at;camera.rotation_euler=(Vector(look)-camera.location).to_track_quat('-Z','Y').to_euler();scene.render.filepath=str(EVIDENCE/(name+'.png'));bpy.ops.render.render(write_still=True)
    hand_path=ASSET/'henry_right_hand.blend'
    with bpy.data.libraries.load(str(hand_path),link=False) as (available,chosen):chosen.objects=['HenryRightHandBare']
    hands=[]
    for ob in chosen.objects:
        bpy.context.collection.objects.link(ob);ob.hide_set(False);ob.hide_render=True;ob.location=Vector((.125,-.025,.285+shift));hands.append(ob)
    bare=next(ob for ob in hands if 'Bare' in ob.name)
    bare.hide_render=False
    camera.data.ortho_scale=.31
    for name,eye in [('grip_bare',(-.48,.12,.43)),('grip_bare_reverse',(.48,-.12,.36))]:
        camera.location=eye;target=Vector((0,-.035,.225));camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler();scene.render.filepath=str(EVIDENCE/(name+'.png'));bpy.ops.render.render(write_still=True)
    for ob in hands:
        ob.hide_render='Glove' in ob.name
        ob.hide_set('Glove' in ob.name)
    bpy.ops.wm.save_as_mainfile(filepath=str(ASSET/'searchlight_with_henry_hand.blend'))


if __name__=='__main__':main()
