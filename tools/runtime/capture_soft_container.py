#!/usr/bin/env python3
"""Capture the isolated #254 lab without loading production autoloads/settings."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default='godot')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--tilt', type=float, default=60.0)
    parser.add_argument('--validate-only', action='store_true')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='hoarbound-soft-container-') as tmp:
        stage = Path(tmp)
        shutil.copyfile(repo / 'scripts/experimental/soft_container_lab.gd', stage / 'lab.gd')
        scene = (repo / 'scenes/experimental/soft_container_lab.tscn').read_text()
        (stage / 'lab.tscn').write_text(scene.replace('res://scripts/experimental/soft_container_lab.gd', 'res://lab.gd'))
        (stage / 'project.godot').write_text('''config_version=5
[application]
config/name="Hoarbound soft container experiment"
run/main_scene="res://lab.tscn"
[display]
window/size/viewport_width=1080
window/size/viewport_height=1080
[rendering]
renderer/rendering_method="gl_compatibility"
[physics]
3d/physics_engine="Jolt Physics"
common/physics_ticks_per_second=240
jolt_physics_3d/simulation/soft_body_point_radius=0.09
jolt_physics_3d/simulation/position_steps=8
''')
        cmd = [args.godot, '--path', str(stage)]
        if args.validate_only:
            subprocess.run(cmd + ['--headless', '--check-only', '--script', 'lab.gd'], check=True)
            return
        with (output / 'godot.log').open('w') as log:
            subprocess.run(cmd + ['--fixed-fps', '24', '--audio-driver', 'Dummy', '--disable-vsync', '--', '--capture', f'--capture-output={output}', f'--tilt={args.tilt}'], stdout=log, stderr=subprocess.STDOUT, check=True)
    capture = json.loads((output / 'capture.json').read_text())
    expected = [(action, body) for body in range(6) for action in ('pick', 'release')]
    actual = [(event['event'], event['body']) for event in capture['events']]
    if len(capture['samples']) != 648 or actual != expected:
        raise RuntimeError('Incomplete capture or drag sequence; inspect capture.json and godot.log')
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-framerate', '24', '-i', str(output / 'frames/frame_%04d.png'), '-vf', 'setpts=PTS/4.5,scale=540:540,pad=1920:540:690:0:color=0x151b25', '-r', '24', '-t', '6', '-an', '-c:v', 'libx264', '-profile:v', 'high', '-level:v', '3.2', '-crf', '27', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(output / 'preview.mp4')], check=True)
    print(output / 'preview.mp4')


if __name__ == '__main__':
    main()
