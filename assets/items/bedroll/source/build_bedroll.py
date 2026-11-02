"""Blender 5.2 review candidate for Henry's folding bedroll.

Frame 1: laid, 18: folded lengthwise, 56: packed roll. Source dimensions
follow the existing 0.75 x 1.9 m gameplay bedroll; the folded roll fits the
0.4 m pack-top mount. This script makes only a Blender review asset.
"""

import bpy
import math
import os
from mathutils import Vector, Quaternion

OUT = os.environ.get("BEDROLL_OUT",os.path.dirname(os.path.abspath(__file__)))
W = 0.75
L = 1.9
SEGMENTS = 18
SEG = L / SEGMENTS
NX = 20
NY = 180

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for datablock in bpy.data.materials:
    bpy.data.materials.remove(datablock)


def material(name, color, rough=0.9, metallic=0.0, fade=None):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    if fade is not None:
        nodes = mat.node_tree.nodes
        links = mat.node_tree.links
        wear = nodes.new("ShaderNodeAttribute")
        wear.attribute_name = "Wear"
        wear.location = (-380, 60)
        broad=nodes.new("ShaderNodeTexNoise")
        broad.inputs["Scale"].default_value=8.0
        broad.inputs["Detail"].default_value=2.0
        broad.location=(-380,-140)
        broad_mix=nodes.new("ShaderNodeMath")
        broad_mix.operation="MULTIPLY_ADD"
        broad_mix.inputs[1].default_value=.31
        broad_mix.location=(-160,-120)
        links.new(broad.outputs["Fac"],broad_mix.inputs[0])
        links.new(wear.outputs["Fac"],broad_mix.inputs[2])
        mix = nodes.new("ShaderNodeMixRGB")
        mix.blend_type = "MIX"
        mix.inputs[1].default_value = (*color, 1.0)
        mix.inputs[2].default_value = (*fade, 1.0)
        mix.location = (-120, 60)
        links.new(broad_mix.outputs["Value"], mix.inputs[0])
        links.new(mix.outputs[0], bsdf.inputs["Base Color"])
        fine=nodes.new("ShaderNodeTexNoise")
        fine.inputs["Scale"].default_value=125.0
        fine.inputs["Detail"].default_value=2.0
        fine.location=(-370,-360)
        bump=nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value=.20
        bump.inputs["Distance"].default_value=.007
        bump.location=(-100,-300)
        links.new(fine.outputs["Fac"],bump.inputs["Height"])
        links.new(bump.outputs["Normal"],bsdf.inputs["Normal"])
    return mat


outer = material("01_Faded_olive_canvas", (0.075, 0.115, 0.065), fade=(0.28, 0.30, 0.16))
inner = material("02_Worn_underside", (0.12, 0.15, 0.09), fade=(0.32, 0.31, 0.19))
edge = material("03_Dark_bound_edge", (0.040, 0.060, 0.042))
repair = material("04_Old_field_repair", (0.12, 0.15, 0.08), fade=(0.23, 0.24, 0.13))
thread = material("05_Stitch_thread", (0.41, 0.38, 0.23))
webbing = material("06_Faded_webbing", (0.070, 0.083, 0.053), fade=(0.21, 0.22, 0.13))
metal = material("07_Dull_brass", (0.20, 0.17, 0.09), rough=0.72, metallic=0.38)
ground = material("Studio_ground", (0.064, 0.078, 0.087), rough=1.0)


def wear_value(u, v):
    edge_dist = min(u, 1-u, v, 1-v)
    edge_wear = max(0.0, 1.0-edge_dist/0.12)*0.43
    broad = 0.12 + 0.20*math.sin(7.4*v+2.1*u)*math.sin(5.8*u-4.0*v)
    patch_a = 0.28*math.exp(-((u-0.23)**2/0.025+(v-0.72)**2/0.012))
    patch_b = 0.31*math.exp(-((u-0.82)**2/0.035+(v-0.23)**2/0.016))
    return max(0.0, min(0.83, edge_wear+broad+patch_a+patch_b))


def fabric_height(x, y):
    # Three broad creases, with the edges held by the binding.
    side = math.sin(math.pi*(x+W/2)/W)**2
    creases = 0.0080*math.sin(2*math.pi*(y+0.95)/0.61 + 1.3*x)
    crease_end = 0.0050*math.exp(-((y-0.66)/0.14)**2)
    crease_mid = -0.0040*math.exp(-((y+0.18+0.16*x)/0.10)**2)
    quilt = 0.0020*math.cos(4*math.pi*x/W)
    channels=sum(-.0055*math.exp(-((y-yy)/.032)**2) for yy in (-.72,-.28,.25,.67))
    return 0.030 + side*(creases+crease_end+crease_mid+quilt+channels)


arm_data = bpy.data.armatures.new("Bedroll_Armature_Data")
arm = bpy.data.objects.new("Bedroll_Armature", arm_data)
bpy.context.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
arm.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
for i in range(SEGMENTS):
    y0 = -L/2+i*SEG
    roll = arm_data.edit_bones.new(f"Roll_{i:02d}")
    roll.head = (0, y0, 0.03)
    roll.tail = (0, y0+SEG, 0.03)
    if i:
        roll.parent = arm_data.edit_bones[f"Roll_{i-1:02d}"]
        roll.use_connect = True
    for side, sign in (("L", -1), ("R", 1)):
        wing = arm_data.edit_bones.new(f"Fold_{side}_{i:02d}")
        wing.head = (0, y0+SEG/2, 0.03)
        wing.tail = (sign*W/2, y0+SEG/2, 0.03)
        wing.parent = roll
bpy.ops.object.mode_set(mode="OBJECT")
arm.select_set(False)
arm.show_in_front = True
arm.hide_render = True


skinned=[]


def skin(obj, positions):
    names = [f"Fold_{side}_{i:02d}" for side in ("L", "R") for i in range(SEGMENTS)]
    groups = {name: obj.vertex_groups.new(name=name) for name in names}
    for vi, (x,y,z) in enumerate(positions):
        side = "L" if x < -1e-5 else "R"
        t = (y+L/2)/SEG-0.5
        lo = math.floor(t)
        blend = t-lo
        a = min(max(lo, 0), SEGMENTS-1)
        b = min(max(lo+1, 0), SEGMENTS-1)
        if a == b:
            groups[f"Fold_{side}_{a:02d}"].add([vi], 1.0, "REPLACE")
        else:
            groups[f"Fold_{side}_{a:02d}"].add([vi], 1.0-blend, "REPLACE")
            groups[f"Fold_{side}_{b:02d}"].add([vi], blend, "REPLACE")
    mod = obj.modifiers.new("Fold_and_roll_skin", "ARMATURE")
    mod.object = arm
    skinned.append(obj)


def build_half(name, xlo, xhi):
    verts=[]; faces=[]; mats=[]; uvs=[]
    for layer in ("top", "bottom"):
        for j in range(NY+1):
            y=-L/2+L*j/NY
            for i in range(NX+1):
                x=xlo+(xhi-xlo)*i/NX
                if abs(x)>W*.31:
                    sign=1 if x>0 else -1
                    edge_weight=((abs(x)-W*.31)/(W*.19))**2
                    x+=sign*edge_weight*(.004*math.sin(13*y)+.003*math.sin(29*y+2.5))
                z=fabric_height(x,y) if layer=="top" else 0.003+0.0012*math.sin(3*y+2*x)
                verts.append((x,y,z))
                uvs.append(((x+W/2)/W,(y+L/2)/L))
    count=(NX+1)*(NY+1)
    def idx(i,j,layer=0): return layer*count+j*(NX+1)+i
    for j in range(NY):
        for i in range(NX):
            faces.append((idx(i,j),idx(i+1,j),idx(i+1,j+1),idx(i,j+1)));mats.append(0)
            faces.append((idx(i,j,1),idx(i,j+1,1),idx(i+1,j+1,1),idx(i+1,j,1)));mats.append(1)
    for j in range(NY):
        for i in (0,NX):
            if i==0: f=(idx(i,j),idx(i,j+1),idx(i,j+1,1),idx(i,j,1))
            else: f=(idx(i,j),idx(i,j,1),idx(i,j+1,1),idx(i,j+1))
            faces.append(f);mats.append(2)
    for i in range(NX):
        for j in (0,NY):
            if j==0:f=(idx(i,j),idx(i,j,1),idx(i+1,j,1),idx(i+1,j))
            else:f=(idx(i,j),idx(i+1,j),idx(i+1,j,1),idx(i,j,1))
            faces.append(f);mats.append(2)
    mesh=bpy.data.meshes.new(name+"Mesh")
    mesh.from_pydata(verts,[],faces);mesh.update()
    obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj)
    for mat in (outer,inner,edge):mesh.materials.append(mat)
    for poly,mi in zip(mesh.polygons,mats):poly.material_index=mi;poly.use_smooth=True
    uv=mesh.uv_layers.new(name="BedrollUV")
    for poly in mesh.polygons:
        for loop_idx in poly.loop_indices:
            uv.data[loop_idx].uv=uvs[mesh.loops[loop_idx].vertex_index]
    attr=mesh.color_attributes.new(name="Wear",type="FLOAT_COLOR",domain="POINT")
    for i,(u,v) in enumerate(uvs):
        w=wear_value(u,v)
        attr.data[i].color=(w,w,w,1.0)
    skin(obj,verts)
    return obj


pad_left=build_half("Pad_left_fold",-W/2,0.0)
pad_right=build_half("Pad_right_fold",0.0,W/2)


def add_patch(name, x0,x1,y0,y1,mat):
    verts=[];faces=[];uvs=[]
    nx=5;ny=13
    for j in range(ny+1):
        y=y0+(y1-y0)*j/ny
        for i in range(nx+1):
            x=x0+(x1-x0)*i/nx
            if i==0:x+=0.005*math.sin(19*y)
            if i==nx:x+=0.004*math.sin(17*y+1)
            verts.append((x,y,fabric_height(x,y)+0.0025))
            uvs.append(((x+W/2)/W,(y+L/2)/L))
    for j in range(ny):
        for i in range(nx):
            a=j*(nx+1)+i;faces.append((a,a+1,a+nx+2,a+nx+1))
    mesh=bpy.data.meshes.new(name+"Mesh");mesh.from_pydata(verts,[],faces);mesh.update()
    obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj)
    mesh.materials.append(mat)
    for p in mesh.polygons:p.use_smooth=True
    uv=mesh.uv_layers.new(name="BedrollUV")
    for p in mesh.polygons:
        for li in p.loop_indices:uv.data[li].uv=uvs[mesh.loops[li].vertex_index]
    attr=mesh.color_attributes.new(name="Wear",type="FLOAT_COLOR",domain="POINT")
    for i,(u,v) in enumerate(uvs):
        w=min(.75,wear_value(u,v)+.2);attr.data[i].color=(w,w,w,1)
    skin(obj,verts)
    return obj


add_patch("Old_repair_patch",0.13,0.33,0.27,0.61,repair)
add_patch("Small_repair_patch",-0.31,-0.13,-0.65,-0.40,inner)


def patch_stitches(name,x0,x1,y0,y1):
    verts=[];faces=[]
    for j in range(4):
        if j<2:
            x=x0+.011 if j==0 else x1-.011
            count=int((y1-y0)/.018)
            points=[(x,y0+.015+(y1-y0-.03)*i/max(count-1,1),0,1) for i in range(count)]
        else:
            y=y0+.011 if j==2 else y1-.011
            count=int((x1-x0)/.018)
            points=[(x0+.015+(x1-x0-.03)*i/max(count-1,1),y,1,0) for i in range(count)]
        for x,y,dx,dy in points:
            a=len(verts)
            for sx,sy in ((-.004,-.0015),(.004,-.0015),(.004,.0015),(-.004,.0015)):
                xx=x+sx*dx+sy*dy;yy=y+sx*dy+sy*dx
                verts.append((xx,yy,fabric_height(xx,yy)+.004))
            faces.append((a,a+1,a+2,a+3))
    mesh=bpy.data.meshes.new(name+"Mesh");mesh.from_pydata(verts,[],faces);mesh.update()
    obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj)
    mesh.materials.append(thread);skin(obj,verts)
    return obj


patch_stitches("Repair_stitches",.13,.33,.27,.61)
patch_stitches("Small_repair_stitches",-.31,-.13,-.65,-.40)


def add_seam(name, points, width=0.003):
    verts=[];faces=[]
    for x,y in points:
        z=fabric_height(x,y)+0.002
        verts.extend([(x-width/2,y,z),(x+width/2,y,z)])
    for i in range(len(points)-1):
        a=2*i;faces.append((a,a+1,a+3,a+2))
    mesh=bpy.data.meshes.new(name+"Mesh");mesh.from_pydata(verts,[],faces);mesh.update()
    obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj)
    mesh.materials.append(thread);skin(obj,verts)
    return obj


for x in (-W/2+0.019,W/2-0.019):
    add_seam("Edge_stitch_"+("L" if x<0 else "R"),[(x,-L/2+0.02+j*(L-.04)/90) for j in range(91)])
for y in (-L/2+0.024,L/2-0.024):
    add_seam("End_stitch_"+("Near" if y<0 else "Far"),[(-W/2+0.02+j*(W-.04)/70,y) for j in range(71)])
for i,y in enumerate((-.72,-.28,.25,.67)):
    add_seam(f"Quilt_channel_{i}",[(-W/2+.030+j*(W-.060)/70,y+.004*math.sin(8*j/70+i)) for j in range(71)],width=.0025)


root=bpy.data.objects.new("Bedroll_Root",None)
bpy.context.collection.objects.link(root)
arm.parent=root
for obj in skinned:
    obj.parent=root

for obj in skinned:
    for frame,hidden in ((1,False),(53,False),(54,True),(56,True)):
        obj.hide_render=hidden
        obj.keyframe_insert(data_path="hide_render",frame=frame)


def show_only_during(obj, start, end):
    """Keep the animated sheet until its clean, sewn rolled endpoint takes over."""
    for frame, visible in ((1, False), (start-1, False), (start, True), (end, True)):
        obj.hide_render = not visible
        obj.keyframe_insert(data_path="hide_render", frame=frame)


def key_pose(frame, fold_angle, roll_scale):
    bpy.context.scene.frame_set(frame)
    for i in range(SEGMENTS):
        if i==0: angle=0.0
        elif i<6:angle=1.31
        elif i<12:angle=1.03
        else:angle=0.84
        roll=arm.pose.bones[f"Roll_{i:02d}"]
        roll.rotation_mode="QUATERNION"
        roll.rotation_quaternion=Quaternion((1,0,0),angle*roll_scale)
        roll.keyframe_insert(data_path="rotation_quaternion",frame=frame)
        for side in ("L","R"):
            fold=arm.pose.bones[f"Fold_{side}_{i:02d}"]
            fold.rotation_mode="QUATERNION"
            if side=="L":
                # Convert world Y (length axis) to the fold bone's local frame.
                axis=fold.bone.matrix_local.to_3x3().inverted() @ Vector((0,1,0))
                fold.rotation_quaternion=Quaternion(axis,fold_angle)
            else:fold.rotation_quaternion=Quaternion((1,0,0),0)
            fold.keyframe_insert(data_path="rotation_quaternion",frame=frame)


key_pose(1,0,0)
key_pose(18,math.pi,0)
key_pose(56,math.pi,1)
scene=bpy.context.scene
scene.frame_start=1;scene.frame_end=56
root.location=(0,0,0);root.keyframe_insert(data_path="location",frame=1)
root.keyframe_insert(data_path="location",frame=18)
scene.frame_set(56)
bpy.context.view_layer.update()


def evaluated_bounds(objs):
    dg=bpy.context.evaluated_depsgraph_get()
    coords=[]
    for obj in objs:
        evaluated=obj.evaluated_get(dg)
        mesh=evaluated.to_mesh()
        coords.extend(evaluated.matrix_world @ v.co for v in mesh.vertices)
        evaluated.to_mesh_clear()
    return [min(v[i] for v in coords) for i in range(3)],[max(v[i] for v in coords) for i in range(3)]


lo,hi=evaluated_bounds([pad_left,pad_right])
root.location=(-(lo[0]+hi[0])/2,-(lo[1]+hi[1])/2,0.02-lo[2])
root.keyframe_insert(data_path="location",frame=56)
bpy.context.view_layer.update()
lo,hi=evaluated_bounds([pad_left,pad_right])
print("ROLLED_BOUNDS",tuple(round(v,3) for v in lo),tuple(round(v,3) for v in hi),flush=True)

# Keep the curled sheet above the floor throughout the roll. The long bone
# chain otherwise drives the halfway curl below Z=0 even though both endpoint
# poses are grounded.
for frame in range(18,54):
    scene.frame_set(frame)
    bpy.context.view_layer.update()
    mid_lo,_=evaluated_bounds([pad_left,pad_right])
    root.location.z=.004-(mid_lo[2]-root.location.z)
    root.keyframe_insert(data_path="location",index=2,frame=frame)
scene.frame_set(56)


def strap(name,x,flat_x,folded_x):
    n=32;verts=[];faces=[]
    cy=(lo[1]+hi[1])/2;cz=(lo[2]+hi[2])/2
    ry=(hi[1]-lo[1])/2+0.01;rz=(hi[2]-lo[2])/2+0.01
    for j in range(n+1):
        t=j/n
        y=-0.94+0.54*t
        for xx in (flat_x-0.018,flat_x+0.018):verts.append((xx,y,0.048))
    for j in range(n):
        a=2*j;faces.append((a,a+1,a+3,a+2))
    mesh=bpy.data.meshes.new(name+"Mesh");mesh.from_pydata(verts,[],faces);mesh.update()
    obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj)
    mesh.materials.append(webbing)
    obj.shape_key_add(name="Unfastened")
    folded=obj.shape_key_add(name="Lengthwise_folded")
    for j in range(n+1):
        for k,xx in enumerate((folded_x-.018,folded_x+.018)):
            folded.data[2*j+k].co=(xx,-0.94+0.54*j/n,0.064)
    folded.value=0;folded.keyframe_insert(data_path="value",frame=1)
    folded.value=1;folded.keyframe_insert(data_path="value",frame=18)
    folded.keyframe_insert(data_path="value",frame=53)
    folded.value=0;folded.keyframe_insert(data_path="value",frame=54)
    key=obj.shape_key_add(name="Wrapped")
    for j in range(n+1):
        theta=2*math.pi*j/n
        for k,xx in enumerate((x-0.018,x+0.018)):
            key.data[2*j+k].co=(xx,cy+ry*math.cos(theta),cz+rz*math.sin(theta))
    key.value=0;key.keyframe_insert(data_path="value",frame=1)
    key.keyframe_insert(data_path="value",frame=18)
    key.value=1;key.keyframe_insert(data_path="value",frame=56)
    for frame,hidden in ((1,False),(18,False),(20,True),(53,True),(54,True),(56,True)):
        obj.hide_render=hidden;obj.keyframe_insert(data_path="hide_render",frame=frame)
    return obj


strap("Left_webbing_band",-0.11,-0.25,0.25)
strap("Right_webbing_band",0.11,0.11,0.11)


def cube(name,loc,scale,mat):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
    ob=bpy.context.object;ob.name=name;ob.dimensions=scale
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    ob.data.materials.append(mat)
    bevel=ob.modifiers.new("Soft_used_edges","BEVEL")
    bevel.width=min(scale)*.16;bevel.segments=2
    ob.modifiers.new("Weighted_normals","WEIGHTED_NORMAL")
    return ob


for x,flat_x,fold_x in ((-.11,-.25,.25),(.11,.11,.11)):
    buckle=cube("Dull_buckle",(x,(lo[1]+hi[1])/2,(lo[2]+hi[2])/2+(hi[2]-lo[2])/2+.018),(.046,.05,.008),metal)
    packed=buckle.location.copy()
    buckle.location=(flat_x,-.48,.055);buckle.keyframe_insert(data_path="location",frame=1)
    buckle.location=(fold_x,-.48,.070);buckle.keyframe_insert(data_path="location",frame=18)
    buckle.location=packed;buckle.keyframe_insert(data_path="location",frame=56)
    for frame,hidden in ((1,False),(18,False),(20,True),(53,True),(54,True),(56,True)):
        buckle.hide_render=hidden;buckle.keyframe_insert(data_path="hide_render",frame=frame)


# A clean, sewn packed endpoint.  The armature supplies the folding motion;
# this surface replaces the pinched skinning at the last two frames.  It uses
# the same outer-canvas/underside palette and exact backpack-scale bounds.
def packed_mesh(name, verts, faces, mats, wear=None):
    mesh=bpy.data.meshes.new(name+"Mesh")
    mesh.from_pydata(verts,[],faces);mesh.update()
    obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj)
    for mat in mats:mesh.materials.append(mat)
    for poly in mesh.polygons:poly.use_smooth=True
    if wear is not None:
        attr=mesh.color_attributes.new(name="Wear",type="FLOAT_COLOR",domain="POINT")
        for i,w in enumerate(wear):attr.data[i].color=(w,w,w,1)
    show_only_during(obj,54,56)
    return obj


CY=.0;CZ=.155;R=.148;HW=.188
verts=[];faces=[];wear=[]
NR=96;NA=36
for i in range(NA+1):
    x=-HW+2*HW*i/NA
    for j in range(NR+1):
        a=2*math.pi*j/NR
        wrinkle=.003*math.sin(5*a+23*x)+.0023*math.sin(11*a-41*x)
        radius=R+wrinkle
        verts.append((x,CY+radius*math.sin(a),CZ+radius*math.cos(a)))
        fade=.16+.22*max(0,math.sin(3.7*a+14*x)*math.cos(2.3*a-18*x))
        fade+=.23*math.exp(-((a-4.55)/.48)**2-((x+.035)/.10)**2)
        fade+=.26*math.exp(-((a-5.75)/.34)**2-((x-.04)/.08)**2)
        wear.append(min(.76,fade))
for i in range(NA):
    for j in range(NR):
        a=i*(NR+1)+j;faces.append((a,a+NR+1,a+NR+2,a+1))
packed_mesh("Packed_creased_canvas",verts,faces,[outer],wear)


def spiral_end(sign):
    # Cloth edge spirals continuously from the central hollow to the hem.
    turns=3.05;n=420
    backing=[(sign*(HW-.007),CY,CZ)]
    for j in range(97):
        a=2*math.pi*j/96
        backing.append((sign*(HW-.007),CY+.146*math.sin(a),CZ+.146*math.cos(a)))
    backing_faces=[(0,j,j+1) if sign>0 else (0,j+1,j) for j in range(1,97)]
    packed_mesh(f"Packed_{'right' if sign>0 else 'left'}_end_backing",backing,backing_faces,[inner])
    for label,thick,offset,mat in (("Shadow",.035,0,edge),("Fold",.028,sign*.0015,inner)):
        verts=[];faces=[]
        for i in range(n+1):
            t=i/n;a=-.3+2*math.pi*turns*t
            radius=.022+(.120*t)
            for delta in (-thick/2,thick/2):
                rr=radius+delta
                depth=.004*math.sin(3*a)+.004*t
                verts.append((sign*(HW+offset+depth),CY+rr*math.sin(a),CZ+rr*math.cos(a)))
        for i in range(n):
            k=2*i
            face=(k,k+1,k+3,k+2) if sign>0 else (k,k+2,k+3,k+1)
            faces.append(face)
        packed_mesh(f"Packed_{'right' if sign>0 else 'left'}_spiral_{label}",verts,faces,[mat])
    # A small, dark hollow reads as the compressed centre of the pad.
    verts=[(sign*(HW-.002),CY,CZ)]
    for j in range(49):
        a=2*math.pi*j/48;verts.append((sign*(HW-.002),CY+.022*math.sin(a),CZ+.022*math.cos(a)))
    faces=[(0,j,j+1) if sign>0 else (0,j+1,j) for j in range(1,49)]
    packed_mesh(f"Packed_{'right' if sign>0 else 'left'}_centre",verts,faces,[edge])


for sign in (-1,1):spiral_end(sign)


def rolled_band(x):
    verts=[];faces=[];n=96
    for j in range(n+1):
        a=2*math.pi*j/n
        rr=R+.006+.002*math.sin(5*a+23*x)
        for xx in (x-.019,x+.019):
            verts.append((xx,CY+rr*math.sin(a),CZ+rr*math.cos(a)))
    for j in range(n):
        k=2*j;faces.append((k,k+2,k+3,k+1))
    obj=packed_mesh(f"Packed_webbing_{x:+.2f}",verts,faces,[webbing])
    # Buckle frame has an open centre, with a short tongue crossing the strap.
    for j,(dx,dy,dz,sx,sy,sz) in enumerate((
        (-.024,0,0,.007,.047,.006),(.024,0,0,.007,.047,.006),
        (0,-.022,0,.05,.006,.006),(0,.022,0,.05,.006,.006),
        (0,0,.004,.025,.004,.005),
    )):
        bar=cube(f"Packed_buckle_{x:+.2f}_{j}",(x+dx,dy,CZ+R+.015+dz),(sx,sy,sz),metal)
        show_only_during(bar,54,56)


for x in (-.11,.11):rolled_band(x)


def packed_repair():
    verts=[];faces=[];nx=12;ny=24
    x0=-.060;x1=.053;a0=-1.10;a1=-.25
    for i in range(nx+1):
        x=x0+(x1-x0)*i/nx
        for j in range(ny+1):
            a=a0+(a1-a0)*j/ny
            rr=R+.0045+.003*math.sin(5*a+23*x)+.0023*math.sin(11*a-41*x)
            verts.append((x,CY+rr*math.sin(a),CZ+rr*math.cos(a)))
    for i in range(nx):
        for j in range(ny):
            k=i*(ny+1)+j;faces.append((k,k+ny+1,k+ny+2,k+1))
    packed_mesh("Packed_field_repair",verts,faces,[repair])

    # Small field stitches pin the old patch into the outer canvas.
    stitch_verts=[];stitch_faces=[]
    def stitch(x,a,dx,da):
        k=len(stitch_verts)
        for xx,aa in ((x-dx,a-da),(x+dx,a-da),(x+dx,a+da),(x-dx,a+da)):
            rr=R+.007+.003*math.sin(5*aa+23*xx)+.0023*math.sin(11*aa-41*xx)
            stitch_verts.append((xx,CY+rr*math.sin(aa),CZ+rr*math.cos(aa)))
        stitch_faces.append((k,k+1,k+2,k+3))
    for x in (x0+.009,x1-.009):
        for j in range(15):stitch(x,a0+.04+(a1-a0-.08)*j/14,.0025,.003)
    for a in (a0+.035,a1-.035):
        for j in range(8):stitch(x0+.015+(x1-x0-.03)*j/7,a,.0025,.003)
    packed_mesh("Packed_repair_stitches",stitch_verts,stitch_faces,[thread])


packed_repair()


# Studio floor and lights only appear in review renders, not in the exported asset.
studio=bpy.data.collections.new("Studio_render_only")
scene.collection.children.link(studio)
floor=cube("Studio_floor",(0,0,-.035),(5,5,.05),ground)
for col in list(floor.users_collection):col.objects.unlink(floor)
studio.objects.link(floor)


def area(name,loc,power,size,color):
    data=bpy.data.lights.new(name,"AREA");data.energy=power;data.shape="DISK";data.size=size;data.color=color
    obj=bpy.data.objects.new(name,data);studio.objects.link(obj);obj.location=loc
    obj.rotation_euler=(Vector((0,0,0))-obj.location).to_track_quat("-Z","Y").to_euler()


area("Warm_key",(1.8,-2.4,3.0),90,2.5,(1.0,.83,.64))
area("Cold_fill",(-2.2,1.2,2.1),70,3.2,(.54,.68,.88))
area("Rim",(0.5,2.5,2.5),75,1.7,(.82,.91,1.0))
world=bpy.data.worlds.new("Cold_ash_studio")
scene.world=world;world.use_nodes=True
world.node_tree.nodes["Background"].inputs["Color"].default_value=(.11,.14,.17,1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value=.25

cam_data=bpy.data.cameras.new("Review_camera")
cam_data.type="ORTHO"
cam=bpy.data.objects.new("Review_camera",cam_data)
studio.objects.link(cam);scene.camera=cam
scene.render.engine="CYCLES"
FAST=os.environ.get("BEDROLL_FAST") == "1"
scene.cycles.samples=6 if FAST else 12
scene.cycles.use_denoising=True
scene.render.resolution_x=800 if FAST else 960
scene.render.resolution_y=600 if FAST else 720
scene.render.resolution_percentage=100
scene.render.image_settings.file_format="PNG"
scene.view_settings.view_transform="AgX"


def render(name,frame,position,target,ortho):
    scene.frame_set(frame)
    cam.location=position
    cam.rotation_euler=(Vector(target)-cam.location).to_track_quat("-Z","Y").to_euler()
    cam_data.ortho_scale=ortho
    scene.render.filepath=OUT+"/"+name+".png"
    bpy.ops.render.render(write_still=True)
    print("RENDERED",scene.render.filepath,flush=True)


render("bedroll_laid_three_quarter",1,(1.35,-2.2,2.45),(0,0,0),2.35)
if not FAST:
    render("bedroll_laid_top",1,(0,-.01,3.0),(0,0,0),2.90)
    render("bedroll_folded",18,(1.2,-1.7,1.8),(0,0,.02),2.0)
    render("bedroll_mid_roll",36,(1.2,-1.7,1.8),(0,0,.10),2.0)
render("bedroll_rolled_three_quarter",56,(1.15,-1.55,1.05),(0,0,.13),.82)
if not FAST:
    render("bedroll_rolled_end",56,(1.6,-.20,.36),(0,0,.15),.58)

scene.frame_set(1)
scene.render.filepath="//bedroll_laid_three_quarter.png"
scene["status"]="Blender-only geometry and animation review; not integrated into Godot"
scene["states"]="frame 1 laid, 18 lengthwise folded, 56 rolled"
scene["dimensions"]="laid 0.75 x 1.9 m; folded roll fits 0.4 m backpack mount"
bpy.ops.wm.save_as_mainfile(filepath=OUT+"/bedroll_candidate.blend",compress=True)
print("SAVED",OUT+"/bedroll_candidate.blend",flush=True)
os._exit(0)
