"""Flatten the painted Blender masks into portable glTF albedo maps."""
from pathlib import Path
import numpy as np
from PIL import Image

TEX = Path(__file__).resolve().parent.parent / "textures"
wear = np.asarray(Image.open(TEX / "bedroll_wear_mask.png"), dtype=np.float32) / 255
split = np.asarray(Image.open(TEX / "bedroll_split_mask.png"), dtype=np.float32) / 255
for face in ("top", "bottom"):
    base = np.asarray(Image.open(TEX / f"bedroll_{face}_color.png"), dtype=np.float32) / 255
    faded = np.array([.075, .076, .080] if face == "top" else [.070, .071, .077])
    result = base * (1 - wear[..., None]) + faded * wear[..., None]
    crack = np.array([.05, .034, .038])
    result = result * (1 - split[..., None]) + crack * split[..., None]
    Image.fromarray(np.uint8(np.clip(result * 255, 0, 255))).save(TEX / f"bedroll_{face}_game.png")
