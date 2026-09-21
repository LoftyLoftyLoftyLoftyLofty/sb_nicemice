#!/usr/bin/env python3
# Run from anywhere: python3 workbench/hatgen/hatgen.py
import argparse, json, os, random, re, sys
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.abspath(os.path.join(HERE, "..", ".."))
HUMANOID = os.path.join(MOD, "humanoid", "nicemice")
SPECIES = os.path.join(MOD, "species", "nicemice.species")
TAIL = os.path.join(MOD, "items", "armors", "nicemice", "tails", "mouse", "back.png")
TABLE = os.path.join(MOD, "scripts", "nicemice_hat_variants.config")
OUT = os.path.join(HERE, "out")

FRAME = (43, 0, 86, 43)
FRAMES_TEXT = '{\n  "frameList" : {\n    "normal" : [43, 0, 86, 43],\n    "climb" : [43, 172, 86, 215]\n  }\n}\n'
SCALE = 4
LABEL_W = 80
LABEL_H = 14


def frame(path):
	return Image.open(path).convert("RGBA").crop(FRAME)


def species_lists():
	text = open(SPECIES, encoding="utf-8").read()
	ears = re.search(r'"hair"\s*:\s*\[(.*?)\]', text, re.S).group(1)
	hair = re.search(r'"facialHair"\s*:\s*\[(.*?)\]', text, re.S).group(1)
	return re.findall(r'"(\w+)"', ears), re.findall(r'"(\w+)"', hair)


# every {"hex" : "hex", ...} object inside the named array, comments tolerated
def palette_list(text, key):
	start = text.index("[", re.search(r'"%s"\s*:' % key, text).end())
	depth, end = 0, start
	for end in range(start, len(text)):
		depth += {"[": 1, "]": -1}.get(text[end], 0)
		if depth == 0:
			break
	palettes = []
	for block in re.findall(r"\{(.*?)\}", text[start:end], re.S):
		palettes.append({a.lower(): b.lower() for a, b in re.findall(r'"([0-9a-fA-F]{6,8})"\s*:\s*"([0-9a-fA-F]{6,8})"', block)})
	return palettes


def pick(palettes, choice):
	if choice is None:
		return None
	if choice == "random":
		return random.choice(palettes)
	return palettes[int(choice)]


def recolor(image, *palettes):
	out = image.copy()
	px = out.load()
	for palette in palettes:
		if not palette:
			continue
		for y in range(43):
			for x in range(43):
				r, g, b, a = px[x, y]
				to = palette.get("%02x%02x%02x" % (r, g, b))
				if a and to:
					px[x, y] = (int(to[0:2], 16), int(to[2:4], 16), int(to[4:6], 16), a)
	return out


def apply_mask(layer, mask):
	out = layer.copy()
	lp, mp = out.load(), mask.load()
	for y in range(43):
		for x in range(43):
			r, g, b, a = lp[x, y]
			lp[x, y] = (r, g, b, a * mp[x, y][3] // 255)
	return out


# ear pixels the mask would hide, drawn underneath the hat's own pixels
def patch_hat(hat, mask, ears):
	out = hat.copy()
	op, ep, mp = out.load(), ears.load(), mask.load()
	for y in range(43):
		for x in range(43):
			if not op[x, y][3] and ep[x, y][3] and mp[x, y][3] < 128:
				op[x, y] = ep[x, y]
	return out


# layer pixels inside the region, drawn on top of the hat
def stamp_over(hat, region, layer):
	if region is None:
		return hat
	out = hat.copy()
	op, hp, rp = out.load(), layer.load(), region.load()
	for y in range(43):
		for x in range(43):
			if hp[x, y][3] and rp[x, y][3] >= 128:
				op[x, y] = hp[x, y]
	return out


def same_image(a, b):
	for pa, pb in zip(a.getdata(), b.getdata()):
		if pa != pb and (pa[3] or pb[3]):
			return False
	return True


def variant_head_text(base_text, asset_dir, base_name, variant_name, key, mask_name):
	text = base_text
	text = re.sub(r'("itemName"\s*:\s*)"[^"]*"', r'\1"%s"' % variant_name, text, count=1)
	text = re.sub(r'("maleFrames"\s*:\s*)"[^"]*"', r'\1"%s.png"' % key, text, count=1)
	text = re.sub(r'("femaleFrames"\s*:\s*)"[^"]*"', r'\1"%s.png"' % key, text, count=1)
	text = re.sub(r'("mask"\s*:\s*)"[^"]*"', r'\1"%s/%s"' % (asset_dir, mask_name), text, count=1)
	text = re.sub(r'("inventoryIcon"\s*:\s*)"([^/"][^"]*)"', r'\1"%s/\2"' % asset_dir, text, count=1)
	text = re.sub(r'("itemName"[^\n]*\n)', r'\1  "nicemice_hatVariantOf" : "%s",\n' % base_name, text, count=1)
	return text


def build_hat(hat, ear_names, hair_names, args):
	hat_dir = os.path.join(MOD, hat["dir"])
	asset_dir = "/" + hat["dir"].strip("/")
	var_dir = os.path.join(hat_dir, "variants")
	base_text = open(os.path.join(hat_dir, hat["head"]), encoding="utf-8", newline="").read()
	base_name = re.search(r'"itemName"\s*:\s*"([^"]*)"', base_text).group(1)
	base_png = os.path.join(hat_dir, re.search(r'"maleFrames"\s*:\s*"([^"]*)"', base_text).group(1))
	base_mask_name = re.search(r'"mask"\s*:\s*"([^"]*)"', base_text).group(1)
	locked = set(hat.get("locked", []))

	base_sheet = Image.open(base_png).convert("RGBA")
	base_frame = base_sheet.crop(FRAME)

	# most specific file wins: mask_<ear>_<hair>.png, then mask_<hair>.png, then the base hat's mask
	def mask_name_for(ear=None, hair=None):
		names = []
		if ear and hair:
			names.append("mask_%s_%s.png" % (ear, hair))
		if hair:
			names.append("mask_%s.png" % hair)
		for name in names:
			if os.path.exists(os.path.join(hat_dir, name)):
				return name
		return base_mask_name

	def mask_image(name):
		return Image.open(os.path.join(hat_dir, name)).convert("RGBA")

	# most specific file wins: <kind>_<ear>_<hair>.png, then <kind>_<ear>.png (earover) or <kind>_<hair>.png (hairover), then <kind>.png
	def region(kind, ear=None, hair=None):
		own = ear if kind == "earover" else hair
		names = []
		if ear and hair:
			names.append("%s_%s_%s.png" % (kind, ear, hair))
		if own:
			names.append("%s_%s.png" % (kind, own))
		names.append(kind + ".png")
		for name in names:
			path = os.path.join(hat_dir, name)
			if os.path.exists(path):
				return Image.open(path).convert("RGBA")
		return None

	os.makedirs(var_dir, exist_ok=True)
	wanted = set()
	table = {}
	hat_png_for = {}

	# key is "<ear>" or "<ear>_<hair>"; returns the png the sheet should use, or None when the variant isn't needed
	def emit(key, frame_image, fallback_frame, mask_name, fallback_mask_name):
		variant_name = "%s_%s" % (base_name, key)
		png_path = os.path.join(var_dir, key + ".png")
		head_path = os.path.join(var_dir, variant_name + ".head")
		if key in locked:
			if not os.path.exists(png_path):
				sys.exit("locked variant has no png: " + png_path)
			print("  locked   ", key)
		elif same_image(frame_image, fallback_frame) and mask_name == fallback_mask_name:
			return None
		else:
			sheet = base_sheet.copy()
			sheet.paste(frame_image, FRAME[:2])
			sheet.save(png_path)
			print("  generated", key)
		with open(head_path, "w", encoding="utf-8", newline="") as f:
			f.write(variant_head_text(base_text, asset_dir, base_name, variant_name, key, mask_name))
		wanted.update((png_path, head_path))
		return png_path

	def ear_layer(name):
		return frame(os.path.join(HUMANOID, "ears", name + ".png"))

	def hair_layer(name):
		return frame(os.path.join(HUMANOID, "hair", name + ".png"))

	def under(ear, mask_name):
		return patch_hat(base_frame, mask_image(mask_name), ear_layer(ear)) if hat["mode"] == "ears" else base_frame

	# the file's own pixels, drawn last
	def stamp_top(image, ear=None, hair=None):
		top = region("overeverything", ear, hair)
		return stamp_over(image, top, top)

	# hair-over variants shared by every ear that doesn't need its own graphic
	any_frame = {}
	any_png = {}
	any_entries = {}
	any_mask = {}
	mask_for = {}
	for hair in hair_names:
		any_mask[hair] = mask_name_for(hair=hair)
		any_frame[hair] = stamp_over(base_frame, region("hairover", hair=hair), hair_layer(hair))
		any_frame[hair] = stamp_top(any_frame[hair], hair=hair)
		any_png[hair] = emit("any_" + hair, any_frame[hair], base_frame, any_mask[hair], base_mask_name)
		if any_png[hair]:
			any_entries[hair] = "%s_any_%s" % (base_name, hair)
	if any_entries:
		table["any"] = any_entries

	for ear in ear_names:
		ear_frame = stamp_over(under(ear, base_mask_name), region("earover", ear=ear), ear_layer(ear))
		ear_frame = stamp_top(ear_frame, ear=ear)
		ear_png = emit(ear, ear_frame, base_frame, base_mask_name, base_mask_name)
		entries = {}
		if ear_png:
			entries["any"] = "%s_%s" % (base_name, ear)
		for hair in hair_names:
			pair_mask = mask_name_for(ear, hair)
			pair_frame = stamp_over(under(ear, pair_mask), region("earover", ear, hair), ear_layer(ear))
			pair_frame = stamp_over(pair_frame, region("hairover", ear, hair), hair_layer(hair))
			pair_frame = stamp_top(pair_frame, ear, hair)
			if ear_png:
				fallback_frame, fallback_png, fallback_mask = ear_frame, ear_png, base_mask_name
			else:
				fallback_frame, fallback_png, fallback_mask = any_frame[hair], any_png[hair] or base_png, any_mask[hair]
			pair_png = emit("%s_%s" % (ear, hair), pair_frame, fallback_frame, pair_mask, fallback_mask)
			if pair_png:
				entries[hair] = "%s_%s_%s" % (base_name, ear, hair)
			hat_png_for[(ear, hair)] = pair_png or fallback_png
			mask_for[(ear, hair)] = mask_image(pair_mask if pair_png else fallback_mask)
		if entries:
			table[ear] = entries

	if wanted:
		frames_path = os.path.join(var_dir, "default.frames")
		with open(frames_path, "w", encoding="utf-8") as f:
			f.write(FRAMES_TEXT)
		wanted.add(frames_path)

	for name in os.listdir(var_dir):
		path = os.path.join(var_dir, name)
		if path not in wanted:
			os.remove(path)
			print("  removed stale", name)
	if not os.listdir(var_dir):
		os.rmdir(var_dir)

	for gender in ("male", "female"):
		render_sheet(base_name, gender, ear_names, hair_names, hat_png_for, mask_for, locked, args, palette_list(base_text, "colorOptions"))
	return base_name, table


def render_sheet(base_name, gender, ear_names, hair_names, hat_png_for, mask_for, locked, args, hat_palettes):
	cell = 43 * SCALE
	sheet = Image.new("RGBA", (LABEL_W + cell * len(hair_names), LABEL_H + cell * len(ear_names)), (70, 70, 85, 255))
	draw = ImageDraw.Draw(sheet)
	tail = frame(TAIL)
	back_arm = frame(os.path.join(HUMANOID, "backarm.png"))
	head = frame(os.path.join(HUMANOID, gender + "head.png"))
	body = frame(os.path.join(HUMANOID, gender + "body.png"))
	front_arm = frame(os.path.join(HUMANOID, "frontarm.png"))
	body_palettes = palette_list(open(SPECIES, encoding="utf-8").read(), "bodyColor")

	for col, hair in enumerate(hair_names):
		draw.text((LABEL_W + col * cell + 4, 2), hair, fill=(255, 255, 255, 255))
	for row, ear in enumerate(ear_names):
		draw.text((4, LABEL_H + row * cell + 4), ear, fill=(255, 255, 255, 255))
		if ear in locked:
			draw.text((4, LABEL_H + row * cell + 16), "LOCKED", fill=(255, 90, 90, 255))
		for col, hair_name in enumerate(hair_names):
			hat = frame(hat_png_for[(ear, hair_name)])
			mask = mask_for[(ear, hair_name)]
			ears = apply_mask(frame(os.path.join(HUMANOID, "ears", ear + ".png")), mask)
			hair = apply_mask(frame(os.path.join(HUMANOID, "hair", hair_name + ".png")), mask)
			skin = pick(body_palettes, args.bodypalette)
			c = Image.new("RGBA", (43, 43))
			for layer in (tail, back_arm, head, ears, body, hair):
				c.alpha_composite(recolor(layer, skin))
			c.alpha_composite(recolor(hat, pick(hat_palettes, args.hatpalette), skin))
			c.alpha_composite(recolor(front_arm, skin))
			c = c.resize((cell, cell), Image.NEAREST)
			sheet.alpha_composite(c, (LABEL_W + col * cell, LABEL_H + row * cell))
			if "%s_%s" % (ear, hair_name) in locked or ("any_" + hair_name in locked and ear not in locked):
				draw.text((LABEL_W + col * cell + 4, LABEL_H + row * cell + 4), "LOCKED", fill=(255, 90, 90, 255))

	os.makedirs(OUT, exist_ok=True)
	path = os.path.join(OUT, "%s_%s.png" % (base_name, gender))
	sheet.save(path)
	print("  sheet    ", os.path.relpath(path, MOD))


def main():
	parser = argparse.ArgumentParser()
	parser.add_argument("-bodypalette", help="bodyColor index or 'random', applied to the verification sheets only")
	parser.add_argument("-hatpalette", help="colorOptions index or 'random', applied to the verification sheets only")
	args = parser.parse_args()
	ear_names, hair_names = species_lists()
	hats = json.load(open(os.path.join(HERE, "hats.json"), encoding="utf-8"))
	table = {}
	for hat in hats:
		print(hat["head"])
		name, entries = build_hat(hat, ear_names, hair_names, args)
		table[name] = entries
	with open(TABLE, "w", encoding="utf-8") as f:
		json.dump(table, f, indent="\t")
		f.write("\n")
	print("table     ", os.path.relpath(TABLE, MOD))


if __name__ == "__main__":
	main()
