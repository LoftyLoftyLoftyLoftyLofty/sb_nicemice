#!/usr/bin/env python3
# Run from anywhere after census.py: python3 workbench/armorconvert/buildpatches.py
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from census import load_json, CENSUS

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.abspath(os.path.join(HERE, "..", ".."))

PATCH = '[\r\n\t{\r\n\t\t"op" : "add",\r\n\t\t"path" : "/nicemice_convertForNicemice",\r\n\t\t"value" : "%s"\r\n\t}\r\n]'


def mod_item_names():
	names = set()
	for root, dirs, files in os.walk(os.path.join(MOD, "items", "armors")):
		for name in files:
			if os.path.splitext(name)[1] in (".head", ".chest", ".legs", ".back"):
				names.add(load_json(os.path.join(root, name)).get("itemName"))
	return names


def main():
	entries = json.load(open(CENSUS, encoding="utf-8"))
	known = mod_item_names()

	writes, existing, missing = [], [], []
	for e in entries:
		if not e["target"]:
			continue
		if e["target"] not in known:
			missing.append("%s -> %s" % (e["itemName"], e["target"]))
			continue
		out = os.path.join(MOD, e["path"] + ".patch")
		if os.path.exists(out):
			existing.append(e["path"] + ".patch")
			continue
		writes.append((out, PATCH % e["target"]))

	if missing:
		print("targets with no nicemice item, nothing written:")
		for line in missing:
			print("  " + line)
		sys.exit(1)

	for out, text in writes:
		os.makedirs(os.path.dirname(out), exist_ok=True)
		with open(out, "w", encoding="utf-8", newline="") as f:
			f.write(text)
		print("wrote " + os.path.relpath(out, MOD).replace(os.sep, "/"))

	if existing:
		print("\nalready patched, left alone:")
		for line in existing:
			print("  " + line)
	print("\n%d written, %d already present" % (len(writes), len(existing)))


if __name__ == "__main__":
	main()
