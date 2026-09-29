"""Create a synthetic whiteboard photo; contains no user material."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
image = Image.new("RGB", (1280, 900), (185, 184, 177))
draw = ImageDraw.Draw(image)
large = ImageFont.load_default(size=48)
small = ImageFont.load_default(size=36)
draw.polygon([(130, 105), (1165, 82), (1110, 802), (154, 768)], fill=(239, 237, 224))
draw.line([(130, 105), (1165, 82), (1110, 802), (154, 768), (130, 105)], fill=(85, 85, 80), width=6)
draw.rectangle((265, 250, 550, 430), outline=(31, 55, 132), width=9)
draw.text((335, 310), "IDEA", fill=(31, 55, 132), font=large)
draw.rectangle((740, 490, 1015, 680), outline=(50, 82, 139), width=9)
draw.text((772, 550), "ACTION", fill=(50, 82, 139), font=small)
draw.line([(550, 380), (740, 545)], fill=(175, 49, 54), width=10)
draw.polygon([(740, 545), (697, 531), (724, 500)], fill=(175, 49, 54))
draw.text((365, 575), "QUESTION?", fill=(143, 42, 48), font=small)
image = image.filter(ImageFilter.GaussianBlur(0.55))
path = HERE / "demo-board.jpg"
image.save(path, quality=90)
print(path)
