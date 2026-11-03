"""Paint restrained, object-bound colour maps for Hoarbound's old frying pan."""
from pathlib import Path
import math
import random
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent
SIZE = 1024
CX = CY = SIZE // 2


def blend_polygon(image, points, color, alpha):
    layer = Image.new('RGBA', image.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).polygon(points, fill=(*color, alpha))
    return Image.alpha_composite(image, layer)


def arc_points(radius, width, start, end, seed, jitter=0.035):
    rng = random.Random(seed)
    count = max(8, int(abs(end-start) * radius / 18))
    bend = [rng.uniform(-jitter,jitter) for _ in range(count+1)]
    inside=[];outside=[]
    for i in range(count+1):
        angle=start+(end-start)*i/count
        wobble=bend[i]*radius
        inner=radius-width*.5+wobble
        outer=radius+width*.5+wobble
        inside.append((CX+inner*math.cos(angle),CY+inner*math.sin(angle)))
        outside.append((CX+outer*math.cos(angle),CY+outer*math.sin(angle)))
    return inside+list(reversed(outside))


def brush_arc(image, radius, width, start, end, color, alpha, seed):
    return blend_polygon(image,arc_points(radius,width,start,end,seed),color,alpha)


def score_arc(image, radius, start, end, color, alpha, width):
    layer=Image.new('RGBA',image.size,(0,0,0,0))
    points=[]
    for i in range(30):
        a=start+(end-start)*i/29
        r=radius+math.sin(a*6+radius)*1.7
        points.append((CX+r*math.cos(a),CY+r*math.sin(a)))
    ImageDraw.Draw(layer).line(points,fill=(*color,alpha),width=width,joint='curve')
    return Image.alpha_composite(image,layer)


def bowl_texture(kind):
    rng=random.Random(711 if kind=='inside' else 236)
    if kind=='inside':
        image=Image.new('RGBA',(SIZE,SIZE),(37,36,39,255))
        # Cooked-on oil in clustered, broad strokes near the perimeter.
        image=brush_arc(image,340,170,-2.35,-.30,(67,42,37),82,10)
        image=brush_arc(image,340,150,.38,2.28,(59,41,38),72,11)
        image=brush_arc(image,390,100,2.65,4.60,(43,53,67),80,12)
        image=brush_arc(image,215,150,-.50,.60,(51,44,43),65,13)
        for i in range(17):
            angle=rng.uniform(-math.pi,math.pi)
            span=rng.uniform(.15,.57)
            radius=rng.uniform(150,460)
            width=rng.uniform(28,100)
            color=[(78,51,43),(47,58,72),(61,48,46)][i%3]
            image=brush_arc(image,radius,width,angle,angle+span,color,rng.randint(32,78),100+i)
        for i in range(23):
            a=rng.uniform(-math.pi,math.pi);length=rng.uniform(.10,.40)
            image=score_arc(image,rng.uniform(75,370),a,a+length,(114,99,86),rng.randint(38,105),rng.choice([1,2]))
    else:
        image=Image.new('RGBA',(SIZE,SIZE),(49,47,49,255))
        # Broken heat staining stays near the contact edge; the centre is old
        # carbon rather than a bright, perfectly circular target pattern.
        image=brush_arc(image,405,98,-2.55,-.83,(105,69,58),91,21)
        image=brush_arc(image,438,76,.68,1.95,(106,74,62),82,22)
        image=brush_arc(image,392,112,2.81,3.79,(65,74,89),84,23)
        image=brush_arc(image,447,68,4.37,5.30,(88,62,56),76,24)
        # Uneven, hand-placed scoured masses interrupt the old heat marks.
        clusters=[(-248,-142,130,73),(202,-121,166,66),(-65,220,192,91),
                  (262,155,111,68),(-174,51,169,69),(75,-242,137,80),
                  (-36,-67,148,107),(142,49,179,83)]
        for i,(x,y,w,h) in enumerate(clusters):
            points=[(CX+x-w*.59,CY+y-h*.12),(CX+x-w*.25,CY+y-h*.70),
                    (CX+x+w*.28,CY+y-h*.57),(CX+x+w*.64,CY+y-h*.13),
                    (CX+x+w*.40,CY+y+h*.34),(CX+x-w*.06,CY+y+h*.61),
                    (CX+x-w*.63,CY+y+h*.30)]
            color=[(31,33,40),(108,93,85),(48,58,72),(87,58,53)][i%4]
            image=blend_polygon(image,points,color,72 if i%4!=1 else 87)
        for i in range(23):
            angle=rng.uniform(-math.pi,math.pi)
            radius=rng.uniform(90,440)
            width=rng.uniform(20,65)
            color=[(112,87,76),(56,68,83),(34,35,42)][i%3]
            image=brush_arc(image,radius,width,angle,angle+rng.uniform(.11,.35),
                            color,rng.randint(38,84),200+i)
        # Sparse cookware scratches follow the wiping path, not white noise.
        for i in range(29):
            a=rng.uniform(-math.pi,math.pi);length=rng.uniform(.10,.42)
            image=score_arc(image,rng.uniform(85,440),a,a+length,(163,146,127),rng.randint(55,112),rng.choice([1,2]))
    image=image.convert('RGB')
    image.save(OUT/f'pan_{kind}_paint.png',optimize=True)


def handle_texture():
    image=Image.new('RGBA',(1024,256),(35,39,47,255))
    # Broad worn metal on the grip; the forged bar remains dark in silhouette.
    image=blend_polygon(image,[(46,106),(247,99),(442,107),(596,128),
                               (458,153),(232,148),(64,136)],(130,119,111),74)
    image=blend_polygon(image,[(515,91),(684,83),(821,98),(846,119),
                               (666,125),(522,112)],(98,110,123),78)
    image=blend_polygon(image,[(768,148),(912,143),(949,156),(846,171)],
                        (119,105,94),72)
    layer=Image.new('RGBA',image.size,(0,0,0,0))
    draw=ImageDraw.Draw(layer)
    strokes=[((76,95),(277,92),(404,98)),((178,143),(364,137),(542,141)),
             ((460,104),(663,99),(752,105)),((692,158),(830,155),(935,160)),
             ((361,170),(513,166),(644,168)),((824,92),(883,88),(945,92))]
    for points in strokes:
        draw.line(points,fill=(171,149,126,115),width=2)
    draw.arc((826,74,974,188),190,340,fill=(162,139,114,130),width=3)
    image=Image.alpha_composite(image,layer).convert('RGB')
    image.save(OUT/'pan_handle_paint.png',optimize=True)


def side_texture():
    rng=random.Random(509)
    width,height=2048,512
    image=Image.new('RGBA',(width,height),(35,39,47,255))
    # Broad, clustered oxide, bluing and blackened paint; no uniform speckles.
    for i in range(36):
        x=rng.randint(-150,width-100)
        y=rng.choice([rng.randint(35,170),rng.randint(185,390)])
        span=rng.randint(110,420)
        depth=rng.randint(55,195)
        points=[(x,y),(x+span*.26,y-rng.randint(8,40)),
                (x+span*.64,y+rng.randint(-15,20)),(x+span,y+depth*.24),
                (x+span*.71,y+depth),(x+span*.31,y+depth*.8),
                (x-rng.randint(0,40),y+depth*.5)]
        color=[(90,51,41),(51,62,79),(67,52,48),(29,32,40)][i%4]
        image=blend_polygon(image,points,color,rng.randint(52,130))
    layer=Image.new('RGBA',image.size,(0,0,0,0))
    draw=ImageDraw.Draw(layer)
    # Broken bright rim and sparse long scouring marks follow the circumference.
    for i in range(30):
        x=rng.randint(0,width-50)
        y=rng.choice([rng.randint(4,30),rng.randint(170,430)])
        draw.line([(x,y),(x+rng.randint(35,210),y+rng.randint(-8,8))],
                  fill=(152,121,94,rng.randint(45,120)),width=rng.choice([1,2,3]))
    image=Image.alpha_composite(image,layer).convert('RGB')
    image.save(OUT/'pan_side_paint.png',optimize=True)


def inner_wall_texture():
    rng=random.Random(631)
    width,height=2048,512
    image=Image.new('RGBA',(width,height),(37,32,34,255))
    # Old seasoning and heat bluing live on the wall, with a few worn lip marks.
    for i in range(33):
        x=rng.randint(-120,width-60)
        y=rng.randint(20,410)
        span=rng.randint(75,370)
        depth=rng.randint(35,135)
        points=[(x,y),(x+span*.2,y-rng.randint(5,22)),
                (x+span*.65,y+rng.randint(-12,12)),(x+span,y+depth*.45),
                (x+span*.77,y+depth),(x+span*.23,y+depth*.83)]
        color=[(100,58,43),(55,62,78),(74,48,44),(26,28,34)][i%4]
        image=blend_polygon(image,points,color,rng.randint(55,130))
    lip=Image.new('RGBA',image.size,(0,0,0,0))
    draw=ImageDraw.Draw(lip)
    for i in range(21):
        x=rng.randint(0,width-25)
        y=rng.randint(445,500)
        draw.line([(x,y),(x+rng.randint(18,100),y+rng.randint(-5,5))],
                  fill=(153,122,100,rng.randint(75,145)),width=rng.choice([1,2,3]))
    image=Image.alpha_composite(image,lip).convert('RGB')
    image.save(OUT/'pan_inner_wall_paint.png',optimize=True)


if __name__=='__main__':
    bowl_texture('inside')
    bowl_texture('bottom')
    handle_texture()
    side_texture()
    inner_wall_texture()
    print('Painted floor, underside, outer/inner walls and forged handle.')
