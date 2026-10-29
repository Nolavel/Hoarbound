"""Author repeatable NORTHBEAM stencil textures for the Blender source review."""
from pathlib import Path
import random
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/items/searchlight/source/candidate_v2/materials'
FONT='/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf'

def make(name,lines,ink):
    image=Image.new('RGBA',(1024,512));d=ImageDraw.Draw(image)
    for text,y,size in lines:
        font=ImageFont.truetype(FONT,size);bounds=d.textbbox((0,0),text,font=font);width=bounds[2]-bounds[0]
        d.text(((1024-width)/2,y),text,font=font,fill=ink)
    # A few missing ink flecks; no rectangular backing or fabricated certification.
    rng=random.Random(727)
    for i in range(150):
        x=rng.randrange(1024);y=rng.randrange(512);d.line((x,y,x+rng.randrange(2,12),y-1),fill=(0,0,0,0),width=2)
    image.save(OUT/name)

make('rear_marking.png',[('NORTHBEAM',40,126),('PRO-GRADE SEARCHLIGHT',205,53),('HIGH-OUTPUT LED',302,48),('RECHARGEABLE  /  FIELD SERIES',390,36)],(192,188,165,255))
make('side_marking.png',[('NORTHBEAM',145,129),('PRO-GRADE SEARCHLIGHT',315,46)],(25,29,28,255))
