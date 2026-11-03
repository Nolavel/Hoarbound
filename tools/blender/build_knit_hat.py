"""Bake the fitted knit hat into a three-mesh Godot GLB.

Run with Blender 5.2+:
  blender -b --python tools/blender/build_knit_hat.py -- INPUT_BLEND OUTPUT_DIR

INPUT_BLEND is the approved fitting scene (or the generated source/knit_hat.blend).
OUTPUT_DIR receives source/knit_hat.blend, textures, and knit_hat.glb.  The
source is saved after baking, with its three editable meshes and packed maps.
No Henry meshes, badges, eyewear, cameras, or lights are exported.
"""
import os
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def main():
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    if len(args) != 2:
        raise SystemExit('usage: build_knit_hat.py -- INPUT_BLEND OUTPUT_DIR')
    source = Path(args[0]).resolve()
    output = Path(args[1]).resolve()
    if not source.is_file():
        raise FileNotFoundError(source)
    (output / 'source').mkdir(parents=True, exist_ok=True)
    (output / 'textures').mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(source))
    deps = bpy.context.evaluated_depsgraph_get()
    retained = []
    for name in ('Crown', 'Cuff', 'Pom'):
        old = bpy.data.objects.get('Hat_Fitted_' + name) or bpy.data.objects.get('KnitHat_' + name)
        if old is None or old.type != 'MESH':
            raise RuntimeError('Missing hat mesh: ' + name)
        evaluated = old.evaluated_get(deps)
        mesh = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True, depsgraph=deps)
        obj = bpy.data.objects.new('KnitHat_' + name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        obj.matrix_world = old.matrix_world.copy()
        # Bake the approved fit and its shape key into this *new* shipping mesh.
        for v in mesh.vertices:
            v.co = obj.matrix_world @ v.co
        obj.matrix_world.identity()
        if not mesh.materials and old.data.materials:
            for mat in old.data.materials:
                mesh.materials.append(mat)
        retained.append(obj)
    for obj in list(bpy.data.objects):
        if obj not in retained:
            bpy.data.objects.remove(obj, do_unlink=True)
    # Rebuilding from our own clean source temporarily adds .001 to object
    # names. Restore the runtime's stable three-mesh contract after removal.
    for obj, name in zip(retained, ('Crown', 'Cuff', 'Pom')):
        obj.name = 'KnitHat_' + name
        obj.data.name = obj.name + '_Mesh'
    crown, cuff, pom = retained
    # The source pompom has more triangles than all other hat pieces combined.
    # Keep its tuft silhouette while removing sub-pixel internal geometry.
    pom_faces_before = len(pom.data.polygons)
    if pom_faces_before > 12000:
        bpy.ops.object.select_all(action='DESELECT')
        pom.select_set(True)
        bpy.context.view_layer.objects.active = pom
        dec = pom.modifiers.new('GamePomBudget', 'DECIMATE')
        dec.ratio = 0.28
        bpy.ops.object.modifier_apply(modifier=dec.name)
    pom_faces_after = len(pom.data.polygons)
    print('POM_FACES', pom_faces_before, pom_faces_after, flush=True)
    bpy.context.scene['source_asset'] = 'Owner-provided winter hat fitted to Henry; badges removed'
    bpy.context.scene['weave_reference'] = 'https://polyhaven.com/a/knitted_fleece (CC0)'
    bpy.context.scene.render.engine = 'CYCLES'
    bpy.context.scene.cycles.samples = 8
    for obj, label, resolution in ((crown, 'crown', 1024), (cuff, 'cuff', 1024)):
        align_bands_to_cuff(obj, label)
        bake_material(obj, label, resolution, output / 'textures')
    make_pom_material(pom)
    bpy.data.orphans_purge(do_recursive=True)
    for image in bpy.data.images:
        if image.source == 'FILE' and image.users > 0 and image.packed_file is None:
            image.pack()
    source_out = output / 'source' / 'knit_hat.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(source_out))
    bpy.ops.object.select_all(action='SELECT')
    glb = output / 'knit_hat.glb'
    bpy.ops.export_scene.gltf(filepath=str(glb), export_format='GLB', export_animations=False)
    print('HAT_EXPORT', glb, glb.stat().st_size, [(o.name, len(o.data.vertices), len(o.data.polygons)) for o in retained], flush=True)


def align_bands_to_cuff(obj, label):
    """Make the colored rings follow the approved cuff's front/back drop.

    The fitted cuff's top falls about 35 mm from front to back. The original
    Generated-Z ramps ignored that contour, so the rings diverged from the
    cuff in side views. This adjusts only the color-ramp coordinate; stitch
    images, normals, UVs, and all fitted vertices remain unchanged.
    """
    mat = obj.data.materials[0]
    if mat is None or mat.node_tree is None:
        return  # The checked-in clean source has already baked materials.
    nodes = mat.node_tree.nodes
    generated = nodes.get('Separate XYZ')
    band_add = nodes.get('Math.001')
    if generated is None or band_add is None or band_add.type != 'MATH':
        return
    shift = 0.25 if label == 'crown' else 0.35
    links = mat.node_tree.links
    slope = nodes.new('ShaderNodeMath')
    slope.operation = 'MULTIPLY_ADD'
    slope.inputs[1].default_value = shift
    slope.inputs[2].default_value = -shift * 0.5
    level = nodes.new('ShaderNodeMath')
    level.operation = 'ADD'
    links.new(generated.outputs['Y'], slope.inputs[0])
    links.new(generated.outputs['Z'], level.inputs[0])
    links.new(slope.outputs[0], level.inputs[1])
    links.new(level.outputs[0], band_add.inputs[0])


def bake_material(obj, label, resolution, texture_dir):
    mat = obj.data.materials[0]
    if mat is None or not mat.use_nodes:
        raise RuntimeError('Hat material missing on ' + obj.name)
    # Keep the authored UV input fixed while the output atlas uses all 0..1 UV.
    old_uv = obj.data.uv_layers.get('UVMap') or obj.data.uv_layers.active
    if old_uv is None:
        raise RuntimeError('Missing source UV on ' + obj.name)
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    source_uv = nodes.new('ShaderNodeUVMap')
    source_uv.uv_map = old_uv.name
    for node in list(nodes):
        if node.type != 'TEX_COORD':
            continue
        for link in list(node.outputs['UV'].links):
            links.new(source_uv.outputs['UV'], link.to_socket)
    for node in list(nodes):
        if node.type == 'TEX_IMAGE' and not node.inputs['Vector'].is_linked:
            links.new(source_uv.outputs['UV'], node.inputs['Vector'])
    original = [tuple(loop.uv) for loop in old_uv.data]
    lo = [min(uv[i] for uv in original) for i in (0, 1)]
    hi = [max(uv[i] for uv in original) for i in (0, 1)]
    atlas = obj.data.uv_layers.new(name='BakedUV')
    for loop, uv in zip(atlas.data, original):
        loop.uv = ((uv[0] - lo[0]) / (hi[0] - lo[0]), (uv[1] - lo[1]) / (hi[1] - lo[1]))
    obj.data.uv_layers.active = atlas
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    albedo = bpy.data.images.new('KnitHat_' + label + '_albedo', width=resolution, height=resolution, alpha=True)
    albedo.generated_color = (0.0, 0.0, 0.0, 0.0)
    target = nodes.new('ShaderNodeTexImage')
    target.image = albedo
    nodes.active = target
    bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'}, use_clear=True, margin=12)
    albedo.filepath_raw = str(texture_dir / (label + '_albedo.png'))
    albedo.file_format = 'PNG'
    albedo.save()

    normal = bpy.data.images.new('KnitHat_' + label + '_normal', width=resolution, height=resolution, alpha=False)
    normal.generated_color = (0.5, 0.5, 1.0, 1.0)
    normal.colorspace_settings.name = 'Non-Color'
    target.image = normal
    bpy.ops.object.bake(type='NORMAL', normal_space='TANGENT', use_clear=True, margin=12)
    normal.filepath_raw = str(texture_dir / (label + '_normal.png'))
    normal.file_format = 'PNG'
    normal.save()

    # Export a simple glTF-compatible PBR shell.  Runtime swaps it for the
    # project's existing NPR shader while retaining these authored maps.
    clean = bpy.data.materials.new('KnitHat_' + label + '_Baked')
    clean.use_nodes = True
    clean_nodes = clean.node_tree.nodes
    principled = clean_nodes.get('Principled BSDF')
    principled.inputs['Roughness'].default_value = .9
    principled.inputs['Specular IOR Level'].default_value = .2
    albedo_node = clean_nodes.new('ShaderNodeTexImage')
    albedo_node.image = albedo
    normal_node = clean_nodes.new('ShaderNodeTexImage')
    normal_node.image = normal
    normal_node.image.colorspace_settings.name = 'Non-Color'
    normal_map = clean_nodes.new('ShaderNodeNormalMap')
    clean.node_tree.links.new(albedo_node.outputs['Color'], principled.inputs['Base Color'])
    clean.node_tree.links.new(normal_node.outputs['Color'], normal_map.inputs['Color'])
    clean.node_tree.links.new(normal_map.outputs['Normal'], principled.inputs['Normal'])
    obj.data.materials.clear()
    obj.data.materials.append(clean)
    # glTF assigns TEXCOORD_0 by UV-layer order, not Blender's active flag.
    # The original UV has served its baking purpose; ExportUV must be UV0.
    obj.data.uv_layers.remove(old_uv)
    obj.data.uv_layers[0].name = 'ExportUV'


def make_pom_material(obj):
    mat = bpy.data.materials.new('KnitHat_pom_Baked')
    mat.use_nodes = True
    p = mat.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (0.0578, 0.0423, 0.0497, 1.0)
    p.inputs['Roughness'].default_value = .92
    obj.data.materials.clear()
    obj.data.materials.append(mat)


if __name__ == '__main__':
    main()
    os._exit(0)
