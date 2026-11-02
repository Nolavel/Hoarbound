"""Hoarbound padded mat: one sheet rolled by shape keys, then strapped.

Construction follows the owner's opened/rolled padded-mat references.
The connected sheet is never replaced or hidden during the animation.
"""
import bpy, math, os
from mathutils import Vector

OUT=os.environ.get("BEDROLL_OUT",os.path.dirname(os.path.abspath(__file__)))
os.makedirs(OUT,exist_ok=True)
FAST=os.environ.get("BEDROLL_FAST")=="1"
W,L=.75,1.90
NX,NY=24,160
BOTTOM,TOP=.003,.035
R0,PITCH,DENT=.027,.032,.010
ROLL_START,ROLL_END,STRAP_SLIDE_END,END=8,64,70,76
ROLL_FRAMES=tuple(range(ROLL_START+1,ROLL_END+1))
TEXTURE_DIR=os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)),"..","textures"))

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


def painted_fabric(name,color_file,fade):
    m=mat(name,(.075,.085,.06),rough=.95)
    n=m.node_tree.nodes;links=m.node_tree.links;bs=n.get("Principled BSDF")
    def tex(filename,mask=False):
        path=os.path.join(TEXTURE_DIR,filename)
        if not os.path.exists(path):raise FileNotFoundError(path)
        img=bpy.data.images.load(path,check_existing=True)
        if mask:img.colorspace_settings.name="Non-Color"
        img.pack()
        node=n.new("ShaderNodeTexImage");node.image=img;node.interpolation="Linear"
        return node
    base=tex(color_file)
    wear=tex("bedroll_wear_mask.png",True)
    split=tex("bedroll_split_mask.png",True)
    strength=n.new("ShaderNodeMath");strength.operation="MULTIPLY"
    strength.inputs[1].default_value=1.25
    links.new(wear.outputs["Color"],strength.inputs[0])
    worn=n.new("ShaderNodeMixRGB");worn.blend_type="MIX"
    worn.inputs[2].default_value=(*fade,1)
    links.new(strength.outputs[0],worn.inputs[0]);links.new(base.outputs["Color"],worn.inputs[1])
    crack=n.new("ShaderNodeMixRGB");crack.blend_type="MIX"
    crack.inputs[2].default_value=(.026,.034,.028,1)
    links.new(split.outputs["Color"],crack.inputs[0]);links.new(worn.outputs["Color"],crack.inputs[1])
    links.new(crack.outputs["Color"],bs.inputs["Base Color"])
    fiber=n.new("ShaderNodeTexNoise");fiber.inputs["Scale"].default_value=72
    fiber.inputs["Detail"].default_value=2
    fiber_bump=n.new("ShaderNodeBump")
    fiber_bump.inputs["Strength"].default_value=.08
    fiber_bump.inputs["Distance"].default_value=.0008
    links.new(fiber.outputs["Fac"],fiber_bump.inputs["Height"])
    bump=n.new("ShaderNodeBump");bump.inputs["Strength"].default_value=.14
    bump.inputs["Distance"].default_value=.0015
    links.new(fiber_bump.outputs["Normal"],bump.inputs["Normal"])
    links.new(split.outputs["Color"],bump.inputs["Height"])
    links.new(bump.outputs["Normal"],bs.inputs["Normal"])
    return m


canvas=painted_fabric("Painted_olive_canvas","bedroll_top_color.png",(.25,.22,.14))
underside=painted_fabric("Painted_dark_underside","bedroll_bottom_color.png",(.20,.20,.13))
binding=mat("Bound_edge",(.035,.044,.032))
webbing=mat("Black_woven_straps",(.023,.026,.024),(.062,.064,.054))
metal=mat("Dull_buckle",(.23,.21,.15),rough=.78,metallic=.35)
floor_m=mat("Studio_floor",(.048,.057,.063))


def height(x,y,top):
    if not top:return BOTTOM+.0003*math.sin(5*y+2*x)
    # Five padded sections like the opened reference, with shallow stitched channels.
    seams=(-L/2+k*L/5 for k in range(1,5))
    transverse=-.006*sum(math.exp(-((y-seam)/.027)**2) for seam in seams)
    transverse+=.003*math.sin(math.pi*((y+L/2)%(L/5))/(L/5))
    worn=.0007*math.sin(13*y+2*x)*math.sin(7*x-4*y)
    sag=-.0018*math.exp(-((x+.18)/.08)**2-((y+.35)/.15)**2)
    sag-=.0016*math.exp(-((x-.23)/.07)**2-((y-.53)/.12)**2)
    return TOP+transverse+worn+sag


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
            faces.append((at(i,j),at(i+1,j),at(i+1,j+1),at(i,j+1)));materials.append(0)
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
        faces.append((a,b,c,d) if layer==0 else (d,c,b,a));materials.append(0 if layer==0 else 1)
mesh=bpy.data.meshes.new("Bedroll_Continuous_Sheet_Mesh")
mesh.from_pydata(vertices,[],faces);mesh.update()
sheet=bpy.data.objects.new("Bedroll_Continuous_Sheet",mesh)
bpy.context.collection.objects.link(sheet)
for m in (canvas,underside,binding):mesh.materials.append(m)
for poly,mi in zip(mesh.polygons,materials):poly.material_index=mi;poly.use_smooth=True
color=mesh.color_attributes.new(name="Wear",type="FLOAT_COLOR",domain="POINT")
for i,v in enumerate(wears):color.data[i].color=(v,v,v,1)
uv=mesh.uv_layers.new(name="Sheet_UV")
for poly in mesh.polygons:
    for loop in poly.loop_indices:
        x,y,_=vertices[mesh.loops[loop].vertex_index]
        uv.data[loop].uv=((x+W/2)/W,(y+L/2)/L)
soft_edge=sheet.modifiers.new("Soft_padded_perimeter","BEVEL")
soft_edge.width=.006
soft_edge.segments=3
weight=mesh.attributes.new(name="bevel_weight_edge",type="FLOAT",domain="EDGE")
for i,edge in enumerate(mesh.edges):
    a,b=(vertices[j] for j in edge.vertices)
    along_side=abs(a[0])>W/2-.012 and abs(b[0])>W/2-.012
    across_end=abs(a[1])>L/2-.001 and abs(b[1])>L/2-.001
    if along_side or across_end:weight.data[i].value=1
soft_edge.limit_method="WEIGHT"


def radius(s):return math.sqrt(R0*R0+PITCH*s/math.pi)
def arc(s):return 2*math.pi*(radius(s)-R0)/PITCH
def groove(x,compression):
    return DENT*compression*(math.exp(-((x+.22)/.023)**2)+math.exp(-((x-.22)/.023)**2))


def sheet_world(x,y,z,p,compression=0):
    """Position of the same padded sheet as the roll grows from one end."""
    zflat=z
    s=y+L/2;l=L*p
    if s>l or p<=0:return x,y,zflat
    theta=math.pi+arc(l)-arc(s)
    if p>.90 and s>l-.08:
        stage=min(1,(p-.90)/.10)
        tip=min(1,max(0,(s-(l-.08))/.08))
        theta-=.20*stage*tip*tip*(3-2*tip)
    rr=radius(s)+(TOP-zflat)-groove(x,compression)
    # Broad fabric irregularity breaks the machined-cylinder silhouette.
    rr-=.003*math.exp(-((abs(x)-W/2)/.035)**2)
    rr+=.002*math.sin(14*x+2.2*theta)*math.sin(1.7*theta)
    cy=-L/2+l;cz=radius(l)+TOP
    return x,cy+rr*math.sin(theta),cz+rr*math.cos(theta)


def sheet_pose(x,y,z,p,compression=0):
    _,yy,zz=sheet_world(x,y,z,p,compression)
    return (x,yy,zz)


def add_roll_keys(obj,rest,deform):
    if not obj.data.shape_keys:obj.shape_key_add(name="Basis")
    keys=[]
    for f in ROLL_FRAMES:
        p=(f-ROLL_START)/(ROLL_END-ROLL_START)
        key=obj.shape_key_add(name=f"Roll_{f:02}")
        for i,pos in enumerate(rest):key.data[i].co=deform(*pos,p)
        keys.append(key)
    for frame in range(1,END+1):
        weights=[0.0]*len(keys)
        if ROLL_START<frame<=ROLL_FRAMES[0]:weights[0]=(frame-ROLL_START)/(ROLL_FRAMES[0]-ROLL_START)
        elif frame>=ROLL_END:weights[-1]=1
        elif frame>ROLL_FRAMES[0]:
            hi=next((i for i,f in enumerate(ROLL_FRAMES) if f>=frame),len(keys)-1)
            lo=max(0,hi-1)
            t=(frame-ROLL_FRAMES[lo])/(ROLL_FRAMES[hi]-ROLL_FRAMES[lo]) if hi!=lo else 1
            weights[lo]=1-t;weights[hi]=t
        for key,w in zip(keys,weights):key.value=w;key.keyframe_insert(data_path="value",frame=frame)


add_roll_keys(sheet,vertices,sheet_pose)
# A second key makes strap pressure an explicit event after the clean roll.
compressed=sheet.shape_key_add(name="Strap_Compression")
for i,pos in enumerate(vertices):
    unpressed=sheet_pose(*pos,1,0)
    pressed=sheet_pose(*pos,1,1)
    compressed.data[i].co=tuple(pos[k]+pressed[k]-unpressed[k] for k in range(3))
for frame in (1,ROLL_END,STRAP_SLIDE_END,END):
    t=max(0,min(1,(frame-STRAP_SLIDE_END)/(END-STRAP_SLIDE_END)))
    compressed.value=t*t*(3-2*t)
    compressed.keyframe_insert(data_path="value",frame=frame)
root=bpy.data.objects.new("Bedroll_Root",None)
bpy.context.collection.objects.link(root)
sheet.parent=root
for frame in range(1,END+1):
    p=max(0,min(1,(frame-ROLL_START)/(ROLL_END-ROLL_START)))
    root.location=(0,-L/2*p,0)
    root.keyframe_insert(data_path="location",frame=frame)


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


def smoothstep(t):
    t=max(0,min(1,t))
    return t*t*(3-2*t)


# Removable webbing loops begin outside the packed mat. They slide on after
# frame 64, then pull tight while the sheet's compression key makes two dents.
for label,final_x,start_x in (("Left",-.22,-.65),("Right",.22,.65)):
    n=96;v=[];f=[]
    for j in range(n+1):
        theta=2*math.pi*j/n
        for dx in (-.017,.017):v.append((dx,math.sin(theta),math.cos(theta)))
    for j in range(n):
        a=2*j;f.append((a,a+1,a+3,a+2))
    m=bpy.data.meshes.new(f"Removable_Strap_{label}_Mesh")
    m.from_pydata(v,[],f);m.update();m.materials.append(webbing)
    band=bpy.data.objects.new(f"Removable_Strap_{label}",m)
    bpy.context.collection.objects.link(band);band.parent=root
    solid=band.modifiers.new("Fabric_thickness","SOLIDIFY");solid.thickness=.002

    holder=bpy.data.objects.new(f"Buckle_{label}_Root",None)
    bpy.context.collection.objects.link(holder);holder.parent=root
    bars=[]
    for j,(dx,dy,sx,sy) in enumerate(((-.022,0,.006,.048),(.022,0,.006,.048),(0,-.022,.05,.006),(0,.022,.05,.006))):
        bar=box(f"Buckle_{label}_{j}",(0,0,0),(sx,sy,.005),metal)
        bar.parent=holder;bar.location=(dx,dy,0);bars.append(bar)

    cy=L/2;cz=radius(L)+TOP
    for frame in (1,ROLL_END,*range(ROLL_END+1,END+1)):
        slide=smoothstep((frame-ROLL_END)/(STRAP_SLIDE_END-ROLL_END))
        tighten=smoothstep((frame-STRAP_SLIDE_END)/(END-STRAP_SLIDE_END))
        x=start_x+(final_x-start_x)*slide
        ring_radius=.215+(.165-.215)*tighten
        band.location=(x,cy,cz)
        band.scale=(1,ring_radius,ring_radius)
        band.keyframe_insert(data_path="location",frame=frame)
        band.keyframe_insert(data_path="scale",frame=frame)
        holder.location=(x,cy,cz+ring_radius+.005)
        holder.keyframe_insert(data_path="location",frame=frame)
        hidden=frame<=ROLL_END
        for part in (band,*bars):
            part.hide_render=hidden;part.hide_viewport=hidden
            part.keyframe_insert(data_path="hide_render",frame=frame)
            part.keyframe_insert(data_path="hide_viewport",frame=frame)


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
    render("02_side",1,(1.15,-1.85,.9),(0,0,.02),2.20)
    render("03_half_roll",36,(1,-1.5,1.2),(0,0,.05),1.65)
    render("04_rolled_clean",ROLL_END,(1.1,-1.5,.85),(0,0,.17),1.30)
    render("05_strapped",END,(1.1,-1.5,.85),(0,0,.17),1.30)
    if not FAST:
        render("06_strap_close",END,(.7,-.75,.55),(.10,0,.20),.52)
        render("07_rolled_end",END,(1.4,-.2,.37),(0,0,.17),.64)
scene.frame_set(1);cam.location=(1.35,-2.25,2.2)
cam.rotation_euler=(Vector((0,0,0))-cam.location).to_track_quat("-Z","Y").to_euler()
cam_data.ortho_scale=2.30
scene.render.filepath="//01_open.png"
scene["prototype"]="Owner's padded mat and rolled blanket image references; 190 x 75 cm adaptation"
scene["states"]="1 open; 8 roll starts; 64 clean roll; 65-76 removable straps compress; one continuous mat mesh"
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,"bedroll_one_sheet.blend"),compress=True)
print("SAVED",os.path.join(OUT,"bedroll_one_sheet.blend"),flush=True)
os._exit(0)
