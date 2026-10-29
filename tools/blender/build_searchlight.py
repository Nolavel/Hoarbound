"""Blender-only material and grip review of the Northbeam searchlight, Blender 5.2+.

Run with -- --skills <blender-skills repo>. The rejected v1 is archived under
assets/items/searchlight/source/intermediate_v1. This stage writes candidate_v2
only; core geometry is approved. Final baking and Godot integration await
material/grip review.
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
        def mathnode(op,a,b):
            n=nodes.new('ShaderNodeMath');n.operation=op
            for i,v in enumerate((a,b)):
                if isinstance(v,(int,float)):n.inputs[i].default_value=v
                else:links.new(v,n.inputs[i])
            return n.outputs[0]
        coord=nodes.new('ShaderNodeTexCoord')
        # Object-bound broad brush strokes: small colour variation, no spot palette.
        stretch=nodes.new('ShaderNodeVectorMath');stretch.operation='MULTIPLY'
        links.new(coord.outputs['Generated'],stretch.inputs[0]);stretch.inputs[1].default_value=(1.4,1.1,2)
        brush=nodes.new('ShaderNodeTexNoise');brush.inputs['Scale'].default_value=2;brush.inputs['Detail'].default_value=1
        links.new(stretch.outputs[0],brush.inputs['Vector'])
        tones=nodes.new('ShaderNodeValToRGB');tones.color_ramp.interpolation='CONSTANT'
        tones.color_ramp.elements[0].position=.36;tones.color_ramp.elements[0].color=(*(c*.88 for c in colour),1)
        tones.color_ramp.elements[1].position=.64;tones.color_ramp.elements[1].color=(*(c*1.09 for c in colour),1)
        mid=tones.color_ramp.elements.new(.47);mid.color=(*colour,1)
        links.new(brush.outputs['Fac'],tones.inputs[0])
        # Wear only where two bounding-box planes meet; interrupted by a chip mask.
        sep=nodes.new('ShaderNodeSeparateXYZ');links.new(coord.outputs['Generated'],sep.inputs[0])
        distances=[mathnode('ABSOLUTE',mathnode('SUBTRACT',sep.outputs[k],.5),0) for k in 'XYZ']
        pairs=[mathnode('MINIMUM',distances[a],distances[b]) for a,b in [(0,1),(1,2),(0,2)]]
        edge=mathnode('GREATER_THAN',mathnode('MAXIMUM',mathnode('MAXIMUM',pairs[0],pairs[1]),pairs[2]),.465)
        noise=nodes.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=42;noise.inputs['Detail'].default_value=2
        links.new(coord.outputs['Generated'],noise.inputs[0])
        clusters=nodes.new('ShaderNodeTexNoise');clusters.inputs['Scale'].default_value=4.5;clusters.inputs['Detail'].default_value=1
        links.new(coord.outputs['Generated'],clusters.inputs[0])
        chips=mathnode('MULTIPLY',mathnode('MULTIPLY',edge,mathnode('GREATER_THAN',clusters.outputs['Fac'],.55)),mathnode('GREATER_THAN',noise.outputs['Fac'],.50))
        mix=nodes.new('ShaderNodeMixRGB');mix.blend_type='MIX';links.new(chips,mix.inputs[0]);links.new(tones.outputs[0],mix.inputs[1]);mix.inputs[2].default_value=(.075,.080,.078,1)
        # Real CC0 industrial paint: retain the industrial scratches but subdue its raw yellow.
        maps=industrial_maps(mat,'PaintedMetal001',coord.outputs['Generated'])
        tint=nodes.new('ShaderNodeHueSaturation');tint.inputs['Saturation'].default_value=.90;tint.inputs['Value'].default_value=.40
        links.new(maps['Color'],tint.inputs['Color'])
        source_mix=nodes.new('ShaderNodeMixRGB');source_mix.inputs[0].default_value=.18
        links.new(mix.outputs[0],source_mix.inputs[1]);links.new(tint.outputs[0],source_mix.inputs[2]);links.new(source_mix.outputs[0],bsdf.inputs['Base Color'])
        links.new(mathnode('ADD',.64,mathnode('MULTIPLY',brush.outputs['Fac'],.15)),bsdf.inputs['Roughness'])
        links.new(mathnode('MAXIMUM',chips,mathnode('MULTIPLY',mathnode('GREATER_THAN',maps['Metalness'],.85),mathnode('GREATER_THAN',clusters.outputs['Fac'],.63))),bsdf.inputs['Metallic'])
        links.new(mathnode('ADD',.56,mathnode('MULTIPLY',maps['Roughness'],.23)),bsdf.inputs['Roughness'])
        normal=nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.10;links.new(maps['NormalGL'],normal.inputs['Color']);links.new(normal.outputs[0],bsdf.inputs['Normal'])
        bsdf.inputs['Specular IOR Level'].default_value=.25
    if name=='M_Battery':
        nodes,links=mat.node_tree.nodes,mat.node_tree.links
        coord=nodes.new('ShaderNodeTexCoord');maps=industrial_maps(mat,'Metal027',coord.outputs['Generated'])
        mix=nodes.new('ShaderNodeMixRGB');mix.inputs[0].default_value=.60;mix.inputs[1].default_value=(*colour,1);links.new(maps['Color'],mix.inputs[2]);links.new(mix.outputs[0],bsdf.inputs['Base Color'])
        links.new(maps['Roughness'],bsdf.inputs['Roughness'])
        normal=nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.12;links.new(maps['NormalGL'],normal.inputs['Color']);links.new(normal.outputs[0],bsdf.inputs['Normal'])
    return mat


def industrial_maps(mat,source,coord):
    outputs={}
    for channel in ['Color','Roughness','Metalness','NormalGL']:
        path=ASSET/'materials'/source/(source+'_1K-JPG_'+channel+'.jpg')
        image=bpy.data.images.load(str(path),check_existing=True)
        image.colorspace_settings.name='sRGB' if channel=='Color' else 'Non-Color'
        image.pack()
        node=mat.node_tree.nodes.new('ShaderNodeTexImage');node.image=image;node.name=source+'_'+channel;node.projection='BOX';node.projection_blend=.18
        mat.node_tree.links.new(coord,node.inputs['Vector']);outputs[channel]=node.outputs['Color']
    return outputs


def marking(name,path,centre,width,height,axis):
    mat=bpy.data.materials.new(name);nodes,links=mat.node_tree.nodes,mat.node_tree.links
    bsdf=next(n for n in nodes if n.type=='BSDF_PRINCIPLED');bsdf.inputs['Roughness'].default_value=.82
    texture=nodes.new('ShaderNodeTexImage');texture.image=bpy.data.images.load(str(path),check_existing=True);texture.image.pack()
    links.new(texture.outputs['Color'],bsdf.inputs['Base Color']);links.new(texture.outputs['Alpha'],bsdf.inputs['Alpha'])
    mat.surface_render_method='DITHERED'
    c=Vector(centre);u=Vector((0,1,0)) if axis=='X' else Vector((1,0,0));v=Vector((0,0,1))
    verts=[c+u*x*width/2+v*y*height/2 for x,y in [(-1,-1),(1,-1),(1,1),(-1,1)]]
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],[(0,1,2,3)]);mesh.update();layer=mesh.uv_layers.new(name='UVMap')
    for loop,uv in zip(layer.data,[(0,0),(1,0),(1,1),(0,1)]):loop.uv=uv
    ob=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(ob);return finish(ob,name,mat)


def finish(ob, name, mat, role='Body', bevel=0.0):
    ob.name = name
    activate([ob])
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if bevel:
        result = STACK.run(objects=[ob.name], preset='midpoly', width=min(bevel,min(ob.dimensions)*.2), segments=1 if name.startswith(('SwitchGuard','SwitchEndGuard','HandleRearMount','HandleFrontMount')) else 2, apply=True)
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
    def bezier(a,b,c,d,steps=9):
        return [tuple((1-t)**3*a[k]+3*(1-t)**2*t*b[k]+3*(1-t)*t*t*c[k]+t**3*d[k] for k in (0,1)) for t in [i/steps for i in range(steps+1)]]
    # Continuous tangent at both shoulders; compact flat landing for the guarded switch.
    path=bezier((-.161,.154),(-.153,.211),(-.145,.238),(-.108,.238))
    path += [(.036,.238),(.072,.238)]
    path += bezier((.072,.238),(.098,.238),(.077,.199),(.077,.154))[1:]
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
    for face in mesh.polygons:face.use_smooth=True
    mesh.set_sharp_from_angle(angle=math.radians(35))
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
    parser=argparse.ArgumentParser();parser.add_argument('--skills',required=True);parser.add_argument('--grip-only',action='store_true');parser.add_argument('--views',default='');args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    skills=Path(args.skills)/'skills'
    for name in ['blender-hardsurface-modeling','blender-retopology-uv','blender-asset-qa','blender-game-optimization']:
        sys.path.insert(0,str(skills/name/'scripts'))
    global STACK, REVIEW_VIEWS
    REVIEW_VIEWS=set(args.views.split(',')) if args.views else None
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
    metal=material('M_Bezel',(.24,.27,.30),.49,1)
    reflector=material('M_Reflector',(.69,.73,.76),.23,1)
    chip=material('M_LED_Die',(.53,.40,.12),.38)
    ceramic=material('M_LED_Ceramic',(.72,.70,.60),.52)
    box('MainHousing',(0,-.054,.090),(.152,.282,.144),paint,bevel=.012)
    box('BatteryBlock',(0,-.193,.092),(.150,.060,.142),rubber,'Battery',.008)
    box('BatteryRearPlate',(0,-.225,.091),(.133,.008,.124),inset,'Battery',.005)
    for x in [-.075,.075]:
        box('SidePanel',(x,-.059,.090),(.009,.186,.112),paint,bevel=.004)
        for y in [-.172,.061]:box('BodyEdgeBumper',(x,y,.088),(.014,.025,.142),rubber,bevel=.003)
        for z in [.063,.075,.087,.099,.111]:box('CoolingSlot',(x*1.07,-.120,z),(.003,.032,.004),rubber,bevel=.0006)
        for y in [-.130,.008]:
            for z in [.052,.132]:cylinder('PanelScrew',(x*1.085,y,z),.003,.003,metal,8,'X')
    # Opposite flank: four distinct charge lamps, protected in a recessed dark panel.
    box('BatteryGaugeFrame',(-.082,-.030,.101),(.010,.090,.035),rubber,bevel=.003)
    box('BatteryGaugeInset',(-.088,-.030,.101),(.003,.077,.024),inset,bevel=.001)
    gauge=material('M_BatteryGaugeAmber',(.75,.42,.075),.46)
    for i in range(4):
        box('BatteryChargeLamp_%d'%(i+1),(-.090,-.058+i*.018,.101),(.002,.007,.014),gauge,bevel=.0008)
    marking('Marking_Rear',ASSET/'materials/rear_marking.png',(0,-.2295,.092),.112,.064,'Y')
    marking('Marking_Side',ASSET/'materials/side_marking.png',(.0800,-.026,.082),.102,.035,'X')
    box('HandleRearMount',(0,-.158,.162),(.038,.035,.012),inset,bevel=.002)
    box('HandleFrontMount',(0,.073,.162),(.038,.027,.012),inset,bevel=.002)
    handle_sweep(paint)
    box('GripRubber',(0,-.036,.238),(.026,.125,.020),rubber,bevel=.003)
    for y in [-.080,-.056,-.032,-.008,.016]:box('GripFineRib',(0,y,.250),(.023,.002,.0015),inset,bevel=.0004)
    # Flush rocker on the front landing, protected from accidental side contact.
    box('SwitchSeat',(0,.055,.245),(.034,.037,.008),rubber,bevel=.003)
    box('PowerButton',(0,.055,.249),(.020,.025,.004),red,'Button',.0015)
    for x in [-.014,.014]:box('SwitchGuard',(x,.055,.250),(.005,.037,.007),rubber,bevel=.0015)
    for y in [.039,.071]:box('SwitchEndGuard',(0,y,.250),(.024,.005,.007),rubber,bevel=.0015)
    # A tapered optical housing, not a cylinder filled by the body cube.
    cylinder('OpticalRearCover',(0,.079,.115),.088,.004,paint,40)
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
    # Each foot must physically enter the main case, not merely overlap in projection.
    from mathutils.bvhtree import BVHTree
    bpy.context.view_layer.update()
    def tree(ob):
        bm=bmesh.new();bm.from_mesh(ob.data);bm.transform(ob.matrix_world);t=BVHTree.FromBMesh(bm);bm.free();return t
    handle=bpy.data.objects['ErgonomicHandle'];case=bpy.data.objects['MainHousing']
    pairs=tree(handle).overlap(tree(case))
    rear=sum(1 for i,j in pairs if (handle.matrix_world @ handle.data.polygons[i].center).y < -.10)
    front=sum(1 for i,j in pairs if (handle.matrix_world @ handle.data.polygons[i].center).y > .03)
    (EVIDENCE/'handle_joint_check.json').write_text(json.dumps({'rear_case_intersections':rear,'front_case_intersections':front,'minimum_foot_z_before_ground_shift_m':.154,'case_top_z_before_ground_shift_m':.162,'nominal_embed_mm':8},indent=2))
    if not rear or not front:raise RuntimeError('Handle foot disconnected from main case')
    names=[o.name for o in PARTS]
    uv=importlib.import_module('uv_pack').run(objects=[n for n in names if not n.startswith('Marking_')],method='smart',res=1024,margin_px=8)
    (EVIDENCE/'uv_review.json').write_text(json.dumps(uv,indent=2))
    report=importlib.import_module('qa_check').run(objects=names,profile='game',eps=.00015,tol=.004)
    (EVIDENCE/'geometry_qa.json').write_text(json.dumps(report,indent=2))
    stats=importlib.import_module('mesh_stats').run(objects=names,budget='pc')
    (EVIDENCE/'model_stats.json').write_text(json.dumps(stats,indent=2))
    metrics={'ground_shift_m':shift,'handle_section_mm':[22,16],'rubber_grip_section_mm':[26,20],'clearance_above_case_mm':(.238-.010-.162)*1000,'reflector_depth_mm':81,'lens_diameter_mm':189.6,'rim_pad_radial_projection_mm':3.5,'hand_source':'henry_right_hand.blend','game_integration':'paused for material and grip review; core geometry approved','hand_rotation_z_degrees':180,'battery_gauge_lamps':4,'handle_shoulders':'tangent-continuous cubic curves','switch':'guarded front landing, recessed rocker','industrial_materials':['ambientCG PaintedMetal001','ambientCG Metal027'],'removed':['side red latches','rear black square']}
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
    views=[] if grip_only else [('front',(0,1,.139),(0,0,.127),.39),('side',(1,-.01,.145),(0,-.016,.127),.56),('perspective',(.58,.77,.42),(0,-.015,.128),.52),('optics',(.16,.8,.24),(0,.145,.115),.29),('opposite_side',(-1,-.01,.145),(0,-.016,.127),.56),('rear_perspective',(-.58,-.77,.42),(0,-.03,.128),.52),('rear',(0,-1,.14),(0,-.22,.105),.30),('switch_detail',(.36,.46,.48),(0,.035,.233),.24),('rear_handle_joint',(.36,-.27,.23),(0,-.157,.172),.13),('front_handle_joint',(.38,.30,.24),(0,.074,.176),.14)]
    for name,at,look,scale in views:
        if REVIEW_VIEWS and name not in REVIEW_VIEWS:continue
        camera.data.ortho_scale=scale;camera.location=at;camera.rotation_euler=(Vector(look)-camera.location).to_track_quat('-Z','Y').to_euler();scene.render.filepath=str(EVIDENCE/(name+'.png'));bpy.ops.render.render(write_still=True)
    hand_path=ASSET/'henry_right_hand.blend'
    with bpy.data.libraries.load(str(hand_path),link=False) as (available,chosen):chosen.objects=['HenryRightHandBare']
    hands=[]
    for ob in chosen.objects:
        bpy.context.collection.objects.link(ob);ob.hide_set(False);ob.hide_render=True;ob.location=Vector((-.125,-.025,.285+shift));ob.rotation_euler.z=math.pi;hands.append(ob)
    bare=next(ob for ob in hands if 'Bare' in ob.name)
    bare.hide_render=False
    camera.data.ortho_scale=.31
    for name,eye in [('grip_bare',(-.48,.12,.43)),('grip_bare_reverse',(.48,-.12,.36))]:
        if REVIEW_VIEWS and name not in REVIEW_VIEWS:continue
        camera.location=eye;target=Vector((0,-.035,.225));camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler();scene.render.filepath=str(EVIDENCE/(name+'.png'));bpy.ops.render.render(write_still=True)
    for ob in hands:
        ob.hide_render='Glove' in ob.name
        ob.hide_set('Glove' in ob.name)
    bpy.ops.wm.save_as_mainfile(filepath=str(ASSET/'searchlight_with_henry_hand.blend'))


if __name__=='__main__':main()
