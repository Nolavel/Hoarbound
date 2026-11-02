"""Hoarbound bedroll: one sheet, folded by a bone, rolled by shape keys.

Real construction: OneTigris LIGHTDREAM fold sequence, USGI attached straps.
No mesh is replaced or hidden during the animation.
"""
import bpy, math, os
from mathutils import Vector

OUT=os.environ.get("BEDROLL_OUT",os.path.dirname(os.path.abspath(__file__)))
os.makedirs(OUT,exist_ok=True)
FAST=os.environ.get("BEDROLL_FAST")=="1"
W,L=.75,1.90
NX,NY=24,160
BOTTOM,TOP,PIVOT=.003,.010,.010
R0,PITCH,DENT=.010,.014,.006
FOLD,END=26,64
ROLL_FRAMES=tuple(range(FOLD+1,END+1))

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for m in bpy.data.materials:bpy.data.materials.remove(m)


def mat(name,base,fade=None,rough=.93,metallic=0):
    m=bpy.data.materials.new(name);m.diffuse_color=(*base,1);m.use_nodes=True
    n=m.node_tree.nodes;links=m.node_tree.links;bs=n.get("Principled BSDF")
    bs.inputs["Base Color"].default_value=(*base,1)
    bs.inputs["Roughness"].default_value=rough
    bs.inputs["Metallic"].default_value=metallic
    if fade:
        a=n.new("ShaderNodeAttribute");a.attribute_name="Wear"
        noise=n.new("ShaderNodeTexNoise");noise.inputs["Scale"].default_value=7
        add=n.new("ShaderNodeMath");add.operation="MULTIPLY_ADD"
        add.inputs[1].default_value=.25
        links.new(noise.outputs["Fac"],add.inputs[0]);links.new(a.outputs["Fac"],add.inputs[2])
        mix=n.new("ShaderNodeMixRGB");mix.inputs[1].default_value=(*base,1)
        mix.inputs[2].default_value=(*fade,1)
        links.new(add.outputs[0],mix.inputs[0]);links.new(mix.outputs[0],bs.inputs["Base Color"])
        fiber=n.new("ShaderNodeTexNoise");fiber.inputs["Scale"].default_value=95
        bump=n.new("ShaderNodeBump");bump.inputs["Strength"].default_value=.16
        bump.inputs["Distance"].default_value=.003
        links.new(fiber.outputs["Fac"],bump.inputs["Height"])
        links.new(bump.outputs["Normal"],bs.inputs["Normal"])
    return m


canvas=mat("Old_olive_canvas",(.14,.15,.095),(.31,.29,.17))
underside=mat("Dark_underside",(.045,.058,.044),(.12,.13,.08))
binding=mat("Bound_edge",(.035,.044,.032))
repair_a=mat("Field_repair_ochre",(.15,.142,.089),(.24,.21,.12))
repair_b=mat("Field_repair_charcoal",(.071,.079,.064),(.13,.14,.10))
webbing=mat("Black_woven_straps",(.023,.026,.024),(.062,.064,.054))
metal=mat("Dull_buckle",(.23,.21,.15),rough=.78,metallic=.35)
floor_m=mat("Studio_floor",(.048,.057,.063))


def height(x,y,top):
    if not top:return BOTTOM+.0003*math.sin(5*y+2*x)
    transverse=-.0023*math.cos(2*math.pi*(y+L/2)/.135)
    worn=.0007*math.sin(13*y+2*x)*math.sin(7*x-4*y)
    return TOP+transverse+worn


def wear(x,y):
    u=(x+W/2)/W;v=(y+L/2)/L
    edge=max(0,1-min(u,1-u,v,1-v)/.09)*.28
    broad=.12+.18*math.sin(5*u+3*v)*math.sin(7*v-2*u)
    rub=.25*math.exp(-((u-.78)**2/.022+(v-.26)**2/.011))
    return min(.8,max(0,edge+broad+rub))


vertices=[];faces=[];materials=[];wears=[]
def half(sign):
    x0,x1=(-W/2,-.003) if sign<0 else (.003,W/2)
    start=len(vertices)
    for layer in (0,1):
        for j in range(NY+1):
            y=-L/2+j*L/NY
            for i in range(NX+1):
                x=x0+(x1-x0)*i/NX
                if abs(x)>.3:x+=math.copysign(.0025*math.sin(18*y+2),x)
                vertices.append((x,y,height(x,y,layer==0)))
                wears.append(wear(x,y))
    n=(NX+1)*(NY+1)
    def at(i,j,layer=0):return start+layer*n+j*(NX+1)+i
    for j in range(NY):
        y=-L/2+(j+.5)*L/NY
        for i in range(NX):
            x=x0+(x1-x0)*(i+.5)/NX
            mi=0
            if sign>0 and .10<x<.28 and -.62<y<-.34:mi=3
            if sign<0 and -.30<x<-.16 and .15<y<.40:mi=4
            if sign<0 and .48<y<.65 and any(abs(x-b)<.026 for b in (-.29,-.09)):mi=5
            faces.append((at(i,j),at(i+1,j),at(i+1,j+1),at(i,j+1)));materials.append(mi)
            faces.append((at(i,j,1),at(i,j+1,1),at(i+1,j+1,1),at(i+1,j,1)));materials.append(1)
    oi=0 if sign<0 else NX
    for j in range(NY):
        f=(at(oi,j),at(oi,j+1),at(oi,j+1,1),at(oi,j,1)) if sign<0 else (at(oi,j),at(oi,j,1),at(oi,j+1,1),at(oi,j+1))
        faces.append(f);materials.append(2)
    for i in range(NX):
        for j in (0,NY):
            f=(at(i,j),at(i,j,1),at(i+1,j,1),at(i+1,j)) if j==0 else (at(i,j),at(i+1,j),at(i+1,j,1),at(i,j,1))
            faces.append(f);materials.append(2)
    return at


li=half(-1);ri=half(1)
for j in range(NY):
    for layer in (0,1):
        a,b,c,d=li(NX,j,layer),ri(0,j,layer),ri(0,j+1,layer),li(NX,j+1,layer)
        faces.append((a,b,c,d) if layer==0 else (d,c,b,a));materials.append(2)
mesh=bpy.data.meshes.new("Bedroll_Continuous_Sheet_Mesh")
mesh.from_pydata(vertices,[],faces);mesh.update()
sheet=bpy.data.objects.new("Bedroll_Continuous_Sheet",mesh)
bpy.context.collection.objects.link(sheet)
for m in (canvas,underside,binding,repair_a,repair_b,webbing):mesh.materials.append(m)
for poly,mi in zip(mesh.polygons,materials):poly.material_index=mi;poly.use_smooth=True
color=mesh.color_attributes.new(name="Wear",type="FLOAT_COLOR",domain="POINT")
for i,v in enumerate(wears):color.data[i].color=(v,v,v,1)
uv=mesh.uv_layers.new(name="Sheet_UV")
for poly in mesh.polygons:
    for loop in poly.loop_indices:
        x,y,_=vertices[mesh.loops[loop].vertex_index]
        uv.data[loop].uv=((x+W/2)/W,(y+L/2)/L)


rig_data=bpy.data.armatures.new("Bedroll_Fold_Rig_Data")
rig=bpy.data.objects.new("Bedroll_Fold_Rig",rig_data)
bpy.context.collection.objects.link(rig)
bpy.context.view_layer.objects.active=rig;rig.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
for name in ("Fold_Left","Rest_Right"):
    b=rig_data.edit_bones.new(name);b.head=(0,-L/2,PIVOT);b.tail=(0,L/2,PIVOT)
bpy.ops.object.mode_set(mode="OBJECT");rig.select_set(False);rig.hide_render=True
left=sheet.vertex_groups.new(name="Fold_Left")
right=sheet.vertex_groups.new(name="Rest_Right")
for i,(x,_,_) in enumerate(vertices):(left if x<0 else right).add([i],1,"REPLACE")
mod=sheet.modifiers.new("Fold_the_same_sheet","ARMATURE");mod.object=rig


def radius(s):return math.sqrt(R0*R0+PITCH*s/math.pi)
def arc(s):return 2*math.pi*(radius(s)-R0)/PITCH
def groove(x,p):
    return DENT*p**6*(math.exp(-((x-.09)/.023)**2)+math.exp(-((x-.29)/.023)**2))


def sheet_world(x,y,z,p):
    """Position after the lengthwise bone fold, before root translation."""
    zflat=2*PIVOT-z if x<0 else z
    s=y+L/2;l=L*p
    if s>=l or p<=0:return abs(x),y,zflat
    theta=math.pi+arc(l)-arc(s)
    rr=radius(s)+(.017-zflat)-groove(abs(x),p)
    cy=-L/2+l;cz=radius(l)+.017
    return abs(x),cy+rr*math.sin(theta),cz+rr*math.cos(theta)


def sheet_prefold(x,y,z,p):
    _,yy,zz=sheet_world(x,y,z,p)
    return (x,yy,2*PIVOT-zz if x<0 else zz)


def add_roll_keys(obj,rest,deform):
    if not obj.data.shape_keys:obj.shape_key_add(name="Basis")
    keys=[]
    for f in ROLL_FRAMES:
        p=(f-FOLD)/(END-FOLD)
        key=obj.shape_key_add(name=f"Roll_{f:02}")
        for i,pos in enumerate(rest):key.data[i].co=deform(*pos,p)
        keys.append(key)
    for frame in range(1,END+1):
        weights=[0.0]*len(keys)
        if FOLD<frame<=ROLL_FRAMES[0]:weights[0]=(frame-FOLD)/(ROLL_FRAMES[0]-FOLD)
        elif frame>ROLL_FRAMES[0]:
            hi=next((i for i,f in enumerate(ROLL_FRAMES) if f>=frame),len(keys)-1)
            lo=max(0,hi-1)
            t=(frame-ROLL_FRAMES[lo])/(ROLL_FRAMES[hi]-ROLL_FRAMES[lo]) if hi!=lo else 1
            weights[lo]=1-t;weights[hi]=t
        for key,w in zip(keys,weights):key.value=w;key.keyframe_insert(data_path="value",frame=frame)


add_roll_keys(sheet,vertices,sheet_prefold)
fold=rig.pose.bones["Fold_Left"];fold.rotation_mode="XYZ"
for f,angle in ((1,0),(12,0),(FOLD,math.pi),(END,math.pi)):
    fold.rotation_euler=(0,angle,0)
    fold.keyframe_insert(data_path="rotation_euler",frame=f)


root=bpy.data.objects.new("Bedroll_Root",None)
bpy.context.collection.objects.link(root)
rig.parent=root;sheet.parent=root
for frame in range(1,END+1):
    p=max(0,min(1,(frame-FOLD)/(END-FOLD)))
    root.location=(-W/4*p,-L/2*p,0)
    root.keyframe_insert(data_path="location",frame=frame)


def strap_pos(x,y,z,p,t):
    folded_x=abs(x)
    # Work in post-fold space, then invert the bone for the shape-key mesh.
    _,sy,sz=sheet_world(folded_x,y,TOP+.010,p)
    if p<=0:return (x,sy,2*PIVOT-sz)
    theta=math.pi+2*math.pi*t
    rb=radius(L*p);cy=-L/2+L*p;cz=rb+.017
    # The strap follows the outer spiral envelope and presses into two grooves.
    rr=rb-PITCH*t+.019-groove(folded_x,p)
    target=(folded_x,cy+rr*math.sin(theta),cz+rr*math.cos(theta))
    u=max(0,min(1,(p-.58)/.42));u=u*u*(3-2*u)
    u*=min(1,t/.06) # sewn end stays attached to the original sheet
    return (x,sy*(1-u)+target[1]*u,2*PIVOT-(sz*(1-u)+target[2]*u))


for label,base_x in (("Left",-.29),("Right",-.09)):
    n=72;v=[];f=[]
    for j in range(n+1):
        y=L/2-.76*j/n
        for x in (base_x-.017,base_x+.017):v.append((x,y,BOTTOM-.002))
    for j in range(n):
        a=2*j;f.append((a,a+1,a+3,a+2))
    m=bpy.data.meshes.new(f"Strap_{label}_Mesh");m.from_pydata(v,[],f);m.update()
    ob=bpy.data.objects.new(f"Strap_{label}",m);bpy.context.collection.objects.link(ob)
    ob.parent=root;m.materials.append(webbing)
    vg=ob.vertex_groups.new(name="Fold_Left");vg.add(list(range(len(v))),1,"REPLACE")
    arm=ob.modifiers.new("Follow_fold_bone","ARMATURE");arm.object=rig
    attr=m.color_attributes.new(name="Wear",type="FLOAT_COLOR",domain="POINT")
    for i in range(len(v)):attr.data[i].color=(.08,.08,.08,1)
    add_roll_keys(ob,v,lambda x,y,z,p:strap_pos(x,y,z,p,(L/2-y)/.76))


def box(name,loc,dims,material,collection=None):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
    ob=bpy.context.object;ob.name=name;ob.dimensions=dims
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    ob.data.materials.append(material)
    be=ob.modifiers.new("Worn_bevel","BEVEL");be.width=min(dims)*.14;be.segments=2
    ob.modifiers.new("Weighted_normals","WEIGHTED_NORMAL")
    if collection:
        for col in list(ob.users_collection):col.objects.unlink(ob)
        collection.objects.link(ob)
    return ob


for label,base_x in (("Left",-.29),("Right",-.09)):
    holder=bpy.data.objects.new(f"Buckle_{label}_Root",None)
    bpy.context.collection.objects.link(holder);holder.parent=root
    for j,(dx,dy,sx,sy) in enumerate(((-.022,0,.006,.048),(.022,0,.006,.048),(0,-.022,.05,.006),(0,.022,.05,.006))):
        bar=box(f"Buckle_{label}_{j}",(0,0,0),(sx,sy,.005),metal)
        bar.parent=holder;bar.location=(dx,dy,0)
    for frame in range(1,END+1):
        p=max(0,min(1,(frame-FOLD)/(END-FOLD)))
        y=L/2-.76*.5
        if frame<FOLD:
            k=max(0,min(1,(frame-12)/(FOLD-12)))
            k=k*k*(3-2*k)
            angle=math.pi*k
            x0,z0=base_x,TOP+.021
            xyz=(math.cos(angle)*x0+math.sin(angle)*(z0-PIVOT),y,
                 -math.sin(angle)*x0+math.cos(angle)*(z0-PIVOT)+PIVOT+.04*k)
        else:
            xx,yy,zz=strap_pos(base_x,y,BOTTOM-.002,p,.5)
            xyz=(abs(xx),yy,2*PIVOT-zz+.008)
        holder.location=xyz;holder.keyframe_insert(data_path="location",frame=frame)


studio=bpy.data.collections.new("Studio_only")
bpy.context.scene.collection.children.link(studio)
box("Studio_floor",(0,0,-.036),(5,5,.05),floor_m,studio)
def light(name,where,power,size,color):
    data=bpy.data.lights.new(name,"AREA");data.energy=power;data.shape="DISK";data.size=size;data.color=color
    ob=bpy.data.objects.new(name,data);studio.objects.link(ob);ob.location=where
    ob.rotation_euler=(Vector((0,0,0))-ob.location).to_track_quat("-Z","Y").to_euler()
light("Warm_key",(1.7,-2.2,2.7),130,2.2,(1,.84,.68))
light("Cold_fill",(-2,1,2.1),70,2.8,(.63,.75,.9))
light("Rim",(.4,2.2,2),63,1.6,(.87,.93,1))
world=bpy.data.worlds.new("Cold_studio")
bpy.context.scene.world=world;world.use_nodes=True
world.node_tree.nodes["Background"].inputs["Color"].default_value=(.12,.14,.16,1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value=.30
cam_data=bpy.data.cameras.new("Review_camera");cam_data.type="ORTHO"
cam=bpy.data.objects.new("Review_camera",cam_data);studio.objects.link(cam)
scene=bpy.context.scene;scene.camera=cam
scene.frame_start=1;scene.frame_end=END
scene.render.engine="CYCLES";scene.cycles.samples=7 if FAST else 16
scene.cycles.use_denoising=True
scene.render.resolution_x=800 if FAST else 1100
scene.render.resolution_y=600 if FAST else 825
scene.render.image_settings.file_format="PNG"
scene.view_settings.view_transform="AgX"
def render(name,frame,eye,target,scale):
    scene.frame_set(frame);cam.location=eye
    cam.rotation_euler=(Vector(target)-cam.location).to_track_quat("-Z","Y").to_euler()
    cam_data.ortho_scale=scale
    scene.render.filepath=os.path.join(OUT,name+".png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED",name,flush=True)
if os.environ.get("BEDROLL_NO_RENDER")!="1":
    render("01_open",1,(1.35,-2.25,2.2),(0,0,0),2.30)
    render("02_folded",FOLD,(1.15,-1.85,1.8),(0,0,.02),2.20)
    render("03_half_roll",42,(1,-1.5,1.2),(0,0,.05),1.65)
    render("04_rolled",END,(.9,-1.2,.7),(0,0,.12),.65)
    if not FAST:render("05_rolled_end",END,(1.4,-.2,.28),(0,0,.11),.46)
scene.frame_set(1);cam.location=(1.35,-2.25,2.2)
cam.rotation_euler=(Vector((0,0,0))-cam.location).to_track_quat("-Z","Y").to_euler()
cam_data.ortho_scale=2.30
scene.render.filepath="//01_open.png"
scene["prototype"]="OneTigris LIGHTDREAM folding; USGI attached straps"
scene["states"]="1 open; 26 folded lengthwise; 64 rolled; one continuous sheet mesh"
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,"bedroll_one_sheet.blend"),compress=True)
print("SAVED",os.path.join(OUT,"bedroll_one_sheet.blend"),flush=True)
os._exit(0)
