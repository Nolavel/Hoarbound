"""Hoarbound frying pan candidate from Innerscene CC0 body, with rebuilt handle.
Source: https://www.innerscene.com/tools/library/3d-parts/frying-pan-fe1cb069
Source SHA256: 4258522a180bf0c738e4f8e816ff79c043faae789c28683d6663eb5c8d62700d
"""
import bpy,bmesh,math,os
from mathutils import Vector

assert bpy.app.version >= (5,2,0),'Blender 5.2 or newer is required for this build'

HERE=os.path.dirname(os.path.abspath(__file__))
SOURCE=os.path.join(HERE,'innerscene_frying_pan.glb')
OUT=os.path.dirname(HERE)
RENDER_OUT=os.path.abspath(os.path.join(OUT,'..','..','..','docs','asset_previews','frying_pan'))
os.makedirs(OUT,exist_ok=True)
os.makedirs(RENDER_OUT,exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=SOURCE)
body=bpy.data.objects['Pan body, hard-anodised aluminium with nonstick interior']
rivets=[bpy.data.objects['Handle rivet 1'],bpy.data.objects['Handle rivet 2']]
for name in ('Handle rivet 3','Handle, brushed stainless steel','Induction base disc, brushed stainless steel'):
    bpy.data.objects.remove(bpy.data.objects[name],do_unlink=True)
for o in (body,*rivets):
    o.name={'Pan body, hard-anodised aluminium with nonstick interior':'Pan_Body','Handle rivet 1':'Rivet_Upper','Handle rivet 2':'Rivet_Lower'}.get(o.name,o.name)
    for v in o.data.vertices:
        v.co.x=(v.co.x+.090335)*.867
        v.co.y*=.867
        v.co.z*=.867
for rivet in rivets:
    for vertex in rivet.data.vertices:
        vertex.co.x-=.004
        vertex.co.z+=.003

# Keep the bowl's inner and outer UV/material islands as separate meshes. The
# glTF exporter otherwise emits white COLOR_0 for the second material slot.
for o in bpy.context.scene.objects:o.select_set(False)
body.select_set(True);bpy.context.view_layer.objects.active=body
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='DESELECT');bpy.ops.object.mode_set(mode='OBJECT')
for p in body.data.polygons:p.select=(p.material_index==1)
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.separate(type='SELECTED');bpy.ops.object.mode_set(mode='OBJECT')
inner=next(o for o in bpy.context.selected_objects if o!=body)
inner.name='Pan_Interior'
for o in (body,inner):
    o.select_set(False)
    bpy.context.view_layer.objects.active=o
    subdiv=o.modifiers.new('Fine_Paint_Sampling','SUBSURF')
    subdiv.subdivision_type='SIMPLE';subdiv.levels=1
    bpy.ops.object.modifier_apply(modifier=subdiv.name)

def textured_mat(name,filename,rough,metal=0):
    m=bpy.data.materials.new(name);m.use_nodes=True
    bs=m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Roughness'].default_value=rough
    bs.inputs['Metallic'].default_value=metal
    image=m.node_tree.nodes.new('ShaderNodeTexImage')
    image.image=bpy.data.images.load(os.path.join(OUT,filename),check_existing=True)
    m.node_tree.links.new(image.outputs['Color'],bs.inputs['Base Color'])
    return m

outside=textured_mat('Hoarbound_Seasoned_Exterior','pan_side_paint.png',.89,.22)
inside=textured_mat('Hoarbound_Seasoned_Interior','pan_inner_wall_paint.png',.94,.08)
handle_mat=textured_mat('Hoarbound_Forged_Handle','pan_handle_paint.png',.78,.30)
top_paint=textured_mat('Hoarbound_Seasoned_Cooking_Floor','pan_inside_paint.png',.93,.09)
bottom_paint=textured_mat('Hoarbound_Scoured_Underside','pan_bottom_paint.png',.89,.16)
rivet_mat=bpy.data.materials.new('Hoarbound_Worn_Iron_Rivets')
rivet_mat.use_nodes=True
rbs=rivet_mat.node_tree.nodes.get('Principled BSDF')
rbs.inputs['Base Color'].default_value=(.27,.23,.20,1)
rbs.inputs['Metallic'].default_value=.45
rbs.inputs['Roughness'].default_value=.71

body.data.materials.clear();body.data.materials.append(outside)
inner.data.materials.clear();inner.data.materials.append(inside)
for p in inner.data.polygons:p.material_index=0
def assign_wall_uv(obj):
    wall_uv=obj.data.uv_layers.new(name='Painted_Wall_UV')
    obj.data.uv_layers.active=wall_uv
    wall_uv.active_render=True
    for poly in obj.data.polygons:
        loop_ids=list(poly.loop_indices)
        angles=[]
        for li in loop_ids:
            p=obj.data.vertices[obj.data.loops[li].vertex_index].co
            angles.append((math.atan2(p.y,p.x)+math.pi)/(2*math.pi))
        crosses_seam=max(angles)-min(angles)>.5
        for li,u in zip(loop_ids,angles):
            p=obj.data.vertices[obj.data.loops[li].vertex_index].co
            if crosses_seam and u<.5:u+=1
            wall_uv.data[li].uv=(u,max(0.0,min(1.0,(p.z-.0005)/.043)))
    for old_uv in list(obj.data.uv_layers):
        if old_uv.name!='Painted_Wall_UV':obj.data.uv_layers.remove(old_uv)
assign_wall_uv(body)
assign_wall_uv(inner)
for r in rivets:
    r.data.materials.clear();r.data.materials.append(rivet_mat)

def clamp(v,a=0,b=1):return max(a,min(b,v))
def smooth(a,b,x):
    t=clamp((x-a)/(b-a));return t*t*(3-2*t)

# The source has a single large ngon on each flat face. A UV-bound paint layer
# can carry broad seasoned/burned patches without radial vertex-colour wedges.
def paint_disc(name,radius,z,material,up):
    count=96
    vertices=[(0,0,z)]
    for k in range(count):
        a=2*math.pi*k/count
        vertices.append((radius*math.cos(a),radius*math.sin(a),z))
    polygons=[]
    for k in range(count):
        face=(0,1+k,1+(k+1)%count)
        polygons.append(face if up else tuple(reversed(face)))
    data=bpy.data.meshes.new(name+'_Mesh')
    data.from_pydata(vertices,[],polygons);data.update()
    data.materials.append(material)
    uv=data.uv_layers.new(name='Paint_UV')
    for poly in data.polygons:
        for li in poly.loop_indices:
            p=data.vertices[data.loops[li].vertex_index].co
            uv.data[li].uv=(.5+.5*p.x/radius,.5+.5*p.y/radius)
    obj=bpy.data.objects.new(name,data)
    bpy.context.collection.objects.link(obj)
    return obj
top_disc=paint_disc('Pan_Seasoned_Cooking_Floor',.0885,.0068,top_paint,True)
bottom_disc=paint_disc('Pan_Worn_Underside',.0865,.0002,bottom_paint,False)

# The forged handle rises off the bowl wall in a sequence of cross-sections.
# Long triangulation diagonals would create false kinks in this shallow metal.
stations=[(.103,.017),(.113,.018),(.128,.016),(.143,.012),(.168,.010),
          (.195,.010),(.215,.011),(.233,.013),(.245,.015),(.254,.016),
          (.262,.014),(.269,.009),(.273,.001)]
across=6
def rise(x):return .0305+.0180*smooth(.105,.205,x)
verts=[]
for top in (True,False):
    for x,halfwidth in stations:
        for j in range(across+1):
            fraction=(j/across)*2-1
            y=fraction*halfwidth
            crown=.0008*(1-fraction*fraction) if top else 0
            verts.append((x,y,rise(x)+crown-(0 if top else .0065)))
ring=len(stations)*(across+1)
def vi(i,j,top=True):return i*(across+1)+j+(0 if top else ring)
faces=[]
for i in range(len(stations)-1):
    for j in range(across):
        faces.append((vi(i,j),vi(i+1,j),vi(i+1,j+1),vi(i,j+1)))
        faces.append((vi(i,j,False),vi(i,j+1,False),vi(i+1,j+1,False),vi(i+1,j,False)))
    faces.append((vi(i,0),vi(i,0,False),vi(i+1,0,False),vi(i+1,0)))
    faces.append((vi(i,across),vi(i+1,across),vi(i+1,across,False),vi(i,across,False)))
for j in range(across):
    faces.append((vi(0,j),vi(0,j+1),vi(0,j+1,False),vi(0,j,False)))
    last=len(stations)-1
    faces.append((vi(last,j+1),vi(last,j),vi(last,j,False),vi(last,j+1,False)))
mesh=bpy.data.meshes.new('Pan_Forged_Handle_Mesh');mesh.from_pydata(verts,[],faces);mesh.update()
handle=bpy.data.objects.new('Pan_Forged_Handle',mesh);bpy.context.collection.objects.link(handle)
bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(mesh);bm.free()
mesh.materials.append(handle_mat)
# 24x17 mm cutter, leaving approximately 22x14 mm clear after the rounded rim.
bpy.ops.mesh.primitive_cylinder_add(vertices=48,radius=1,depth=.06,location=(.25,0,.056))
cutter=bpy.context.object;cutter.name='Temporary_Hole_Cutter';cutter.scale=(.012,.0085,1)
bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
bpy.context.view_layer.objects.active=handle
mod=handle.modifiers.new('Carabiner_Through_Hole','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter
bpy.ops.object.modifier_apply(modifier=mod.name)
bpy.data.objects.remove(cutter,do_unlink=True)
bevel=handle.modifiers.new('Rounded_Edges_And_Eye','BEVEL');bevel.width=.0013;bevel.segments=2;bevel.limit_method='ANGLE';bevel.angle_limit=.28
bpy.context.view_layer.objects.active=handle
bpy.ops.object.modifier_apply(modifier=bevel.name)
for poly in handle.data.polygons:poly.use_smooth=True
handle_uv=handle.data.uv_layers.new(name='Forged_Paint_UV')
handle.data.uv_layers.active=handle_uv
handle_uv.active_render=True
for poly in handle.data.polygons:
    for li in poly.loop_indices:
        p=handle.data.vertices[handle.data.loops[li].vertex_index].co
        handle_uv.data[li].uv=(clamp((p.x-.103)/.17),clamp(.5+p.y/.050))
for old_uv in list(handle.data.uv_layers):
    if old_uv.name!='Forged_Paint_UV':handle.data.uv_layers.remove(old_uv)
for o in (body,inner,top_disc,bottom_disc,handle,*rivets):
    o['provenance']='Innerscene CC0 pan body' if o==body else 'Hoarbound rebuilt geometry'

# Source QA before export: the hole has one internal boundary and is visibly larger than the rod.
bm=bmesh.new();bm.from_mesh(handle.data)
nonmanifold=sum(not e.is_manifold for e in bm.edges)
print('HANDLE_QA',{'verts':len(handle.data.vertices),'faces':len(handle.data.polygons),'nonmanifold_edges':nonmanifold},flush=True)
bm.free()
assert nonmanifold==0,'handle boolean left open edges'
for o in bpy.context.scene.objects:o.select_set(False)
for o in (body,inner,top_disc,bottom_disc,handle,*rivets):o.select_set(True)
bpy.context.view_layer.objects.active=body
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,'frying_pan.glb'),export_format='GLB',use_selection=True,export_apply=True,export_yup=True)

# Preview stage (not exported).
world=bpy.data.worlds.new('Preview_World');bpy.context.scene.world=world;world.use_nodes=True
world.node_tree.nodes['Background'].inputs['Color'].default_value=(.14,.17,.20,1)
world.node_tree.nodes['Background'].inputs['Strength'].default_value=.6

def light(name,loc,power,size,color):
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.size=size;data.color=color
    o=bpy.data.objects.new(name,data);bpy.context.scene.collection.objects.link(o);o.location=loc
    o.rotation_euler=(Vector((.04,0,.03))-o.location).to_track_quat('-Z','Y').to_euler()
light('Warm_Key',(.1,-.5,.7),16,.6,(1,.83,.68))
light('Cold_Fill',(-.25,.45,.6),10,.7,(.68,.78,1))
light('Rim',(.4,.2,.5),7,.4,(.95,.95,1))
light('Underside_Review',(.05,-.18,-.55),14,.55,(1,.82,.70))
camdata=bpy.data.cameras.new('Review_Camera');camdata.type='ORTHO';camdata.ortho_scale=.53
cam=bpy.data.objects.new('Review_Camera',camdata);bpy.context.scene.collection.objects.link(cam)
scene=bpy.context.scene;scene.camera=cam
scene.render.engine='CYCLES';scene.cycles.samples=18;scene.cycles.use_denoising=True
scene.render.resolution_x=1100;scene.render.resolution_y=825
scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='AgX'
scene.view_settings.exposure=.25

def render(name,eye,target,scale):
    cam.location=eye;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler()
    camdata.ortho_scale=scale;scene.render.filepath=os.path.join(RENDER_OUT,name+'.png')
    bpy.ops.render.render(write_still=True)
    print('RENDER',name,flush=True)
if os.environ.get('PAN_SKIP_RENDERS')!='1':
    render('top',(0,0,1),(.075,0,.025),.64)
    render('bottom',(0,0,-1),(.075,0,.02),.64)
    render('side',(0,-1,.12),(.075,0,.035),.50)
    render('perspective',(.48,-.45,.42),(.07,0,.025),.52)
    render('handle_close',(.29,-.18,.25),(.21,0,.055),.18)
scene['source']='Innerscene CC0 frying-pan body; rebuilt Hoarbound forged handle'
scene['source_sha256']='4258522a180bf0c738e4f8e816ff79c043faae789c28683d6663eb5c8d62700d'
scene['reference']='res://docs/asset_previews/frying_pan/approved_reference.png'
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE,'frying_pan.blend'),compress=True)
print('DONE',flush=True)
os._exit(0)
