"""Hoarbound padded mat: one sheet folded lengthwise, rolled, then strapped.

Construction follows the owner's opened/rolled padded-mat references.
The connected sheet is never replaced or hidden during the animation.
"""
import bpy, math, os
from mathutils import Vector

OUT=os.environ.get("BEDROLL_OUT",os.path.dirname(os.path.abspath(__file__)))
os.makedirs(OUT,exist_ok=True)
FAST=os.environ.get("BEDROLL_FAST")=="1"
W,L=.75,1.90
NX,NY=48,160
BOTTOM,TOP=.0025,.006
# The first turn is tucked into an almost solid core; the old 27 mm start
# radius made the end read as a hollow cardboard tube.
R0,PITCH,DENT=.003,.006,.010
FOLD_HINGE=.0065
ROLL_COMPRESSION=.70
FOLD_START,FOLD_END,ROLL_START,ROLL_END,STRAP_SLIDE_END,END=4,22,24,80,86,92
FOLD_FRAMES=tuple(range(FOLD_START+1,FOLD_END+1))
ROLL_FRAMES=tuple(range(ROLL_START,ROLL_END+1))
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
    strength.inputs[1].default_value=1.0
    links.new(wear.outputs["Color"],strength.inputs[0])
    worn=n.new("ShaderNodeMixRGB");worn.blend_type="MIX"
    worn.inputs[2].default_value=(*fade,1)
    links.new(strength.outputs[0],worn.inputs[0]);links.new(base.outputs["Color"],worn.inputs[1])
    crack=n.new("ShaderNodeMixRGB");crack.blend_type="MIX"
    crack.inputs[2].default_value=(.05,.034,.038,1)
    links.new(split.outputs["Color"],crack.inputs[0]);links.new(worn.outputs["Color"],crack.inputs[1])
    links.new(crack.outputs["Color"],bs.inputs["Base Color"])
    indent=tex("bedroll_indent_mask.png",True)
    fiber=tex("bedroll_fiber_height.png",True)
    fiber_bump=n.new("ShaderNodeBump")
    fiber_bump.inputs["Strength"].default_value=.20
    fiber_bump.inputs["Distance"].default_value=.0015
    links.new(fiber.outputs["Color"],fiber_bump.inputs["Height"])
    bump=n.new("ShaderNodeBump");bump.inputs["Strength"].default_value=.20
    bump.inputs["Distance"].default_value=.003
    links.new(fiber_bump.outputs["Normal"],bump.inputs["Normal"])
    links.new(indent.outputs["Color"],bump.inputs["Height"])
    links.new(bump.outputs["Normal"],bs.inputs["Normal"])
    return m


canvas=painted_fabric("Painted_oxblood_brown_canvas","bedroll_top_color.png",(.075,.076,.080))
underside=painted_fabric("Painted_slate_brown_underside","bedroll_bottom_color.png",(.070,.071,.077))
binding=mat("Bound_edge",(.058,.044,.050))
webbing=mat("Charcoal_woven_straps",(.031,.029,.034),(.070,.066,.070))
buckle_polymer=mat("ITW_style_acetal_ladderlock",(.045,.046,.052),rough=.84)
floor_m=mat("Studio_floor",(.048,.057,.063))


def height(x,y,top):
    seams=(-L/2+k*L/5 for k in range(1,5))
    if not top:
        # Compression also reaches the backing, so channels survive on the roll.
        return BOTTOM+.0004*sum(math.exp(-((y-seam)/.027)**2) for seam in seams)
    # Five padded sections like the opened reference, with shallow stitched channels.
    transverse=-.0010*sum(math.exp(-((y-seam)/.027)**2) for seam in seams)
    transverse+=.0006*math.sin(math.pi*((y+L/2)%(L/5))/(L/5))
    worn=.00015*math.sin(13*y+2*x)*math.sin(7*x-4*y)
    # Pressure hollows displace the original vertices, rather than only shading.
    sag=-.0015*math.exp(-2.7*((x+.1575)/.0975)**2-2.7*((y-.361)/.19)**2)
    sag-=.0012*math.exp(-2.7*((x-.18)/.083)**2-2.7*((y+.285)/.17)**2)
    sag-=.0010*math.exp(-2.7*((x-.0225)/.12)**2-2.7*((y-.019)/.133)**2)
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
# A soft sewn leading hem is part of the connected sheet. Its two exposed end
# folds wind tightly into the roll centre; there is no separate cap or plug.
source_vertex_count=len(vertices)
core_final={}
for sign,anchor,hem_x,end_x in ((-1,li(0,0,0),-W/2+.007,-W/2-.012),
                                (1,ri(0,0,0),.010,.012)):
    rows=[]
    for k in range(55):
        t=k/54
        theta=.35+2*math.pi*1.65*t
        middle=.022*(1-t)+.0006*t
        half_width=.006*(1-t)+.0003*t
        row=[]
        for offset in (-half_width,half_width):
            radial=max(.0003,middle+offset)
            idx=len(vertices)
            vertices.append((hem_x,-L/2+.012+.025*t, .008))
            wears.append(.22)
            core_z=math.sqrt(R0*R0+PITCH*L/math.pi)+ROLL_COMPRESSION*(2*FOLD_HINGE-BOTTOM)
            core_final[idx]=(end_x,L/2+radial*math.sin(theta),core_z+radial*math.cos(theta))
            row.append(idx)
        rows.append(row)
    faces.append((anchor,rows[0][0],rows[0][1]));materials.append(0)
    for a,b in zip(rows,rows[1:]):
        faces.append((a[0],b[0],b[1],a[1]) if sign>0 else (a[1],b[1],b[0],a[0]));materials.append(0)
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
soft_edge.width=.0015
soft_edge.segments=3
weight=mesh.attributes.new(name="bevel_weight_edge",type="FLOAT",domain="EDGE")
for i,edge in enumerate(mesh.edges):
    if any(j>=source_vertex_count for j in edge.vertices):continue
    a,b=(vertices[j] for j in edge.vertices)
    along_side=abs(a[0])>W/2-.012 and abs(b[0])>W/2-.012
    across_end=abs(a[1])>L/2-.001 and abs(b[1])>L/2-.001
    if along_side or across_end:weight.data[i].value=1
soft_edge.limit_method="WEIGHT"


def radius(s):return math.sqrt(R0*R0+PITCH*s/math.pi)
def arc(s):return 2*math.pi*(radius(s)-R0)/PITCH
def smoothstep(a,b,x):
    t=min(1,max(0,(x-a)/(b-a)))
    return t*t*(3-2*t)
def groove(x,compression):
    distance=min(abs(x+.11),abs(x-.11))
    # The full 25 mm webbing width presses evenly; the soft lip rises beside it.
    bed=math.exp(-(max(0.0,distance-.0125)/.037)**2)
    lip=math.exp(-((distance-.065)/.018)**2)
    return compression*(DENT*bed-.0018*lip)


def folded_pose(x,y,z,t):
    """Turn the right half over the centre seam; the left half stays rigid."""
    if x<0:return x,y,z
    angle=math.pi*t
    delta=z-FOLD_HINGE
    return x*math.cos(angle)-delta*math.sin(angle),y,FOLD_HINGE+x*math.sin(angle)+delta*math.cos(angle)


def sheet_world(x,y,z,p,compression=0):
    """Position of the already folded double sheet as the roll grows."""
    zflat=z
    s=y+L/2;l=L*p
    if s>l or p<=0:return x,y,zflat
    theta=math.pi+arc(l)-arc(s)
    if p>.90 and s>l-.08:
        stage=min(1,(p-.90)/.10)
        tip=min(1,max(0,(s-(l-.08))/.08))
        theta-=.20*stage*tip*tip*(3-2*tip)
    rr=radius(s)+ROLL_COMPRESSION*(2*FOLD_HINGE-BOTTOM-zflat)-groove(x+W/4,compression)*smoothstep(.76,1.08,s)
    # Broad fabric irregularity breaks the machined-cylinder silhouette.
    rr-=.001*math.exp(-((abs(x+W/4)-W/4)/.035)**2)
    rr+=.0008*math.sin(14*x+2.2*theta)*math.sin(1.7*theta)
    # Broad creases form where the outer wraps are pressed during rolling.
    rr-=.0017*p*math.exp(-((s-1.57)/.10)**2-((x+.16)/.15)**2)
    rr-=.0022*p*math.exp(-((s-1.77)/.12)**2-((x-.10)/.13)**2)
    cy=-L/2+l;cz=radius(l)+ROLL_COMPRESSION*(2*FOLD_HINGE-BOTTOM)
    return x,cy+rr*math.sin(theta),cz+rr*math.cos(theta)


def sheet_pose(x,y,z,p,compression=0):
    folded=folded_pose(x,y,z,1)
    return sheet_world(*folded,p,compression)


def add_roll_keys(obj,rest,deform):
    if not obj.data.shape_keys:obj.shape_key_add(name="Basis")
    keyed=[]
    for f in FOLD_FRAMES:
        t=smoothstep(FOLD_START,FOLD_END,f)
        key=obj.shape_key_add(name=f"Fold_{f:02}")
        for i,pos in enumerate(rest):key.data[i].co=folded_pose(*pos,t)
        keyed.append((f,key))
    for f in ROLL_FRAMES:
        p=(f-ROLL_START)/(ROLL_END-ROLL_START)
        key=obj.shape_key_add(name=f"Roll_{f:02}")
        for i,pos in enumerate(rest):
            if i in core_final:
                t=smoothstep(.65,1,p)
                key.data[i].co=Vector(folded_pose(*pos,1)).lerp(Vector(core_final[i]),t)
            else:
                key.data[i].co=deform(*pos,p)
        keyed.append((f,key))
    for frame in range(1,END+1):
        active=FOLD_END if FOLD_END<frame<ROLL_START else min(frame,ROLL_END)
        for f,key in keyed:
            key.value=float(f==active)
            key.keyframe_insert(data_path="value",frame=frame)


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
    fold=smoothstep(FOLD_START,FOLD_END,frame)
    root.location=(W/4*fold,-L/2*p,0)
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


def ease(t):
    return smoothstep(0,1,t)


# The 25 mm webbing and two-slot ladderlock follow ITW Nexus Jet LL 25's
# published dimensions (25.9 mm webbing, 33.6 x 30.5 x 11.5 mm body).
# The loops enter after the clean roll. Their final shape touches the broad,
# flat-bottomed deformation, instead of floating above a Gaussian groove.
for label,final_x,start_x in (("Left",-W/4-.11,-W/4-.40),
                              ("Right",-W/4+.11,-W/4+.40)):
    n=128;v=[];f=[]
    for j in range(n+1):
        theta=2*math.pi*j/n
        for dx in (-.0125,.0125):v.append((dx,.09*math.sin(theta),.09*math.cos(theta)))
    for j in range(n):
        a=2*j;f.append((a,a+1,a+3,a+2))
    m=bpy.data.meshes.new(f"Removable_Strap_{label}_Mesh")
    m.from_pydata(v,[],f);m.update();m.materials.append(webbing)
    band=bpy.data.objects.new(f"Removable_Strap_{label}",m)
    bpy.context.collection.objects.link(band);band.parent=root
    solid=band.modifiers.new("Fabric_thickness","SOLIDIFY");solid.thickness=.002
    band.shape_key_add(name="Loose")
    tight=band.shape_key_add(name="Conformed_Tight")
    for j in range(n+1):
        theta=2*math.pi*j/n
        contour=.056+.0006*math.sin(theta*3+.6)+.0003*math.cos(theta*5)
        for side in range(2):
            tight.data[2*j+side].co=(v[2*j+side][0],contour*math.sin(theta),contour*math.cos(theta))

    holder=bpy.data.objects.new(f"Buckle_{label}_Root",None)
    bpy.context.collection.objects.link(holder);holder.parent=root
    parts=[]
    bars=((-.0145,0,0,.0025,.0336,.005),(.0145,0,0,.0025,.0336,.005),
          (0,-.0155,0,.0315,.0027,.005),(0,.0155,0,.0315,.0027,.005),
          (0,0,.002,.028,.0045,.007),
          (0,.011,.003,.026,.002,.003))
    for j,(dx,dy,dz,sx,sy,sz) in enumerate(bars):
        bar=box(f"Ladderlock_{label}_{j}",(0,0,0),(sx,sy,sz),buckle_polymer)
        bar.parent=holder;bar.location=(dx,dy,dz);parts.append(bar)
    # The free end goes under the centre bar, back over its grip, then out.
    path=[(-.015,-.003),(-.004,-.003),(.005,.007),(.018,.008),(.045,.001)]
    tv=[];tf=[]
    for yy,zz in path:
        tv.extend(((-.0125,yy,zz),(.0125,yy,zz)))
    for j in range(len(path)-1):
        a=2*j;tf.append((a,a+1,a+3,a+2))
    tail_mesh=bpy.data.meshes.new(f"Threaded_Tail_{label}_Mesh")
    tail_mesh.from_pydata(tv,[],tf);tail_mesh.update();tail_mesh.materials.append(webbing)
    tail=bpy.data.objects.new(f"Threaded_Tail_{label}",tail_mesh)
    bpy.context.collection.objects.link(tail);tail.parent=holder
    tail_solid=tail.modifiers.new("Webbing_thickness","SOLIDIFY");tail_solid.thickness=.0015
    parts.append(tail)

    cy=L/2;cz=radius(L)+ROLL_COMPRESSION*(2*FOLD_HINGE-BOTTOM)
    for frame in (1,ROLL_END,*range(ROLL_END+1,END+1)):
        slide=ease((frame-ROLL_END)/(STRAP_SLIDE_END-ROLL_END))
        tighten=ease((frame-STRAP_SLIDE_END)/(END-STRAP_SLIDE_END))
        x=start_x+(final_x-start_x)*slide
        ring_radius=.09+(.056-.09)*tighten
        band.location=(x,cy,cz)
        band.keyframe_insert(data_path="location",frame=frame)
        tight.value=tighten;tight.keyframe_insert(data_path="value",frame=frame)
        holder.location=(x,cy,cz+ring_radius+.005)
        holder.keyframe_insert(data_path="location",frame=frame)
        hidden=frame<=ROLL_END
        for part in (band,*parts):
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
    render("03_folded",FOLD_END,(1,-1.5,1.2),(0,0,.05),1.65)
    render("03_half_roll",52,(1,-1.5,1.2),(0,0,.05),1.65)
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
scene["states"]="1 open; 4-22 fold lengthwise; 24-80 roll; 81-92 removable straps compress; one continuous mat mesh"
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,"bedroll_one_sheet.blend"),compress=True)
print("SAVED",os.path.join(OUT,"bedroll_one_sheet.blend"),flush=True)
os._exit(0)
