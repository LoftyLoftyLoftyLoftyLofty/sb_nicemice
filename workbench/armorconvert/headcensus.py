#!/usr/bin/env python3
# Run from anywhere: python3 workbench/armorconvert/headcensus.py <unpacked vanilla assets>
import argparse, json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from census import load_json

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(HERE, "headcensus.json")
KEY = "/nicemice_convertForNicemice"


def patched_heads():
	targets = {}
	for root, dirs, files in os.walk(os.path.join(MOD, "items")):
		for name in files:
			if not name.endswith(".head.patch"):
				continue
			path = os.path.join(root, name)
			for op in load_json(path):
				if isinstance(op, dict) and op.get("path") == KEY:
					rel = os.path.relpath(path[:-len(".patch")], MOD).replace(os.sep, "/")
					targets[rel] = op.get("value")
	return targets


def mod_item_names():
	names = set()
	for root, dirs, files in os.walk(os.path.join(MOD, "items", "armors")):
		for name in files:
			if os.path.splitext(name)[1] in (".head", ".chest", ".legs", ".back"):
				names.add(load_json(os.path.join(root, name)).get("itemName"))
	return names


def main():
	parser = argparse.ArgumentParser()
	parser.add_argument("assets", help="root of unpacked vanilla assets (the folder containing items/)")
	args = parser.parse_args()

	armors = os.path.join(args.assets, "items", "armors")
	if not os.path.isdir(armors):
		sys.exit("no items/armors under %s" % args.assets)

	targets = patched_heads()
	known = mod_item_names()

	entries, failures = [], []
	for root, dirs, files in os.walk(armors):
		dirs.sort()
		for name in sorted(files):
			if not name.endswith(".head"):
				continue
			path = os.path.join(root, name)
			rel = os.path.relpath(path, args.assets).replace(os.sep, "/")
			try:
				config = load_json(path)
			except Exception as e:
				failures.append("%s: %s" % (rel, e))
				continue
			target = targets.get(rel)
			entries.append(
			{
				"path": rel,
				"itemName": config.get("itemName", ""),
				"shortdescription": config.get("shortdescription", ""),
				"target": target,
				"targetExists": target in known if target else False
			})

	with open(OUT, "w", encoding="utf-8", newline="\n") as f:
		json.dump(entries, f, indent="\t")
		f.write("\n")

	covered = [e for e in entries if e["target"] and e["targetExists"]]
	broken = [e for e in entries if e["target"] and not e["targetExists"]]
	missing = [e for e in entries if not e["target"]]

	print("%d vanilla heads: %d converted, %d unconverted" % (len(entries), len(covered), len(missing)))
	for e in covered:
		print("  %-40s -> %s" % (e["itemName"], e["target"]))
	if broken:
		print("\npatched to an item the mod doesn't have:")
		for e in broken:
			print("  %-40s -> %s" % (e["itemName"], e["target"]))
	if missing:
		print("\nno nicemice version:")
		for e in missing:
			print("  %-40s %s" % (e["itemName"], e["shortdescription"]))
	if failures:
		print("\nunreadable:")
		for line in failures:
			print("  " + line)
	print("\nwrote %s" % OUT)


if __name__ == "__main__":
	main()
