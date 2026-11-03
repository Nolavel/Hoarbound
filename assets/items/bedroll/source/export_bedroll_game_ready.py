"""Export static snapshots of the same Blender mat for Godot 4.8."""
import bpy
import os
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
TEXTURES = BASE / "textures"
SHEET = bpy.data.objects["Bedroll_Continuous_Sheet"]


def game_material(name, texture=None, color=None):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    principled = material.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Roughness"].default_value = .93
    if texture:
        image = bpy.data.images.load(str(TEXTURES / texture), check_existing=True)
        node = material.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = image
        material.node_tree.links.new(node.outputs["Color"], principled.inputs["Base Color"])
    else:
        principled.inputs["Base Color"].default_value = (*color, 1)
    return material


top = game_material("Bedroll_Oxblood_Brown_Worn", "bedroll_top_game.png")
bottom = game_material("Bedroll_Slate_Brown_Worn", "bedroll_bottom_game.png")
edge = game_material("Bedroll_Bound_Edge", color=(.058, .044, .050))
webbing = game_material("Bedroll_Charcoal_Webbing", color=(.031, .029, .034))
acetal = game_material("Bedroll_Acetal_Ladderlock", color=(.045, .046, .052))
material_map = {"Painted_oxblood_brown_canvas":top, "Painted_slate_brown_underside":bottom,
                "Bound_edge":edge, "Charcoal_woven_straps":webbing,
                "ITW_style_acetal_ladderlock":acetal}


def snapshot(frame, stem):
    bpy.context.scene.frame_set(frame)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    objects = [SHEET] if frame == 1 else [SHEET] + [obj for obj in bpy.data.objects
        if obj.name.startswith(("Removable_Strap_", "Ladderlock_", "Threaded_Tail_")) and obj.type == 'MESH']
    exported = []
    for obj in objects:
        evaluated = obj.evaluated_get(depsgraph)
        mesh = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True, depsgraph=depsgraph)
        copy = bpy.data.objects.new(obj.name + "_Static", mesh)
        bpy.context.scene.collection.objects.link(copy)
        copy.matrix_world = obj.matrix_world.copy()
        # Parent matrices must be resolved by depsgraph, including the animated root.
        copy.matrix_world = evaluated.matrix_world.copy()
        for index, material in enumerate(mesh.materials):
            if material is not None and material.name in material_map:
                mesh.materials[index] = material_map[material.name]
        exported.append(copy)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in exported: obj.select_set(True)
    bpy.context.view_layer.objects.active = exported[0]
    bpy.ops.export_scene.gltf(filepath=str(BASE / (stem + '.glb')), export_format='GLB',
        use_selection=True, export_apply=True, export_yup=True)
    print('EXPORTED', stem, len(exported), sum(len(o.data.vertices) for o in exported), flush=True)
    for obj in exported:
        mesh = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.meshes.remove(mesh)


snapshot(1, 'bedroll_open')
snapshot(92, 'bedroll_packed')
os._exit(0)
