#!/usr/bin/env python3
# Run from anywhere: python3 workbench/armorconvert/census.py <unpacked vanilla assets>
import argparse, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
CENSUS = os.path.join(HERE, "census.json")

SLOTS = {".head": "head", ".chest": "chest", ".legs": "pants", ".back": "back"}
VARIANTS = ("accelerator", "manipulator", "separator")


# Starbound JSON allows // and /* */ comments; strip them outside strings.
def load_json(path):
	text = open(path, encoding="utf-8-sig").read()
	out, i, n, quoted = [], 0, len(text), False
	while i < n:
		c = text[i]
		if quoted:
			out.append(c)
			if c == "\\":
				out.append(text[i + 1])
				i += 1
			elif c == '"':
				quoted = False
		elif c == '"':
			quoted = True
			out.append(c)
		elif text.startswith("//", i):
			i = text.find("\n", i)
			if i < 0:
				break
			continue
		elif text.startswith("/*", i):
			i = text.index("*/", i) + 2
			continue
		else:
			out.append(c)
		i += 1
	return json.loads("".join(out))


def target_for(item_name, slot, rel):
	match = re.search(r"tier([1-6])", item_name)
	if not match or slot == "back":
		return None
	tier = int(match.group(1))
	if tier <= 4:
		return "nicemicetier%d%s" % (tier, slot)
	variants = [v for v in VARIANTS if v in item_name or v in rel]
	if len(variants) != 1:
		return None
	return "nicemicetier%d%s%s" % (tier, variants[0][0], slot)


def main():
	parser = argparse.ArgumentParser()
	parser.add_argument("assets", help="root of unpacked vanilla assets (the folder containing items/)")
	args = parser.parse_args()

	armors = os.path.join(args.assets, "items", "armors")
	if not os.path.isdir(armors):
		sys.exit("no items/armors under %s" % args.assets)

	entries, failures = [], []
	for root, dirs, files in os.walk(armors):
		dirs.sort()
		for name in sorted(files):
			ext = os.path.splitext(name)[1]
			if ext not in SLOTS:
				continue
			path = os.path.join(root, name)
			rel = os.path.relpath(path, args.assets).replace(os.sep, "/")
			try:
				config = load_json(path)
			except Exception as e:
				failures.append("%s: %s" % (rel, e))
				continue
			item_name = config.get("itemName", "")
			slot = SLOTS[ext]
			entries.append(
			{
				"path": rel,
				"itemName": item_name,
				"slot": slot,
				"level": config.get("level"),
				"target": target_for(item_name, slot, rel)
			})

	with open(CENSUS, "w", encoding="utf-8", newline="\n") as f:
		json.dump(entries, f, indent="\t")
		f.write("\n")

	mapped = [e for e in entries if e["target"]]
	tierish = [e for e in entries if not e["target"] and re.search(r"tier\d", e["itemName"])]
	print("%d armor files, %d mapped" % (len(entries), len(mapped)))
	for e in mapped:
		print("  %-40s -> %s" % (e["itemName"], e["target"]))
	if tierish:
		print("\nnamed like tiered armor but unmapped:")
		for e in tierish:
			print("  %-40s %s" % (e["itemName"], e["path"]))
	if failures:
		print("\nunreadable:")
		for line in failures:
			print("  " + line)
	print("\nwrote %s" % CENSUS)


if __name__ == "__main__":
	main()
