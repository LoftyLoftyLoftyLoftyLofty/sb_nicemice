#!/usr/bin/env python3
# Run from anywhere after census.py: python3 workbench/armorconvert/buildreverse.py
import json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from census import load_json, CENSUS

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.abspath(os.path.join(HERE, "..", ".."))
KEY = "nicemice_otherSpeciesConversion"
ANCHOR = re.compile(r'^[ \t]*"tooltipKind"\s*:\s*"[^"]*",[ \t]*\r?\n', re.M)


def mod_items():
	items = {}
	for root, dirs, files in os.walk(os.path.join(MOD, "items", "armors")):
		for name in files:
			if os.path.splitext(name)[1] in (".head", ".chest", ".legs", ".back"):
				path = os.path.join(root, name)
				items[load_json(path).get("itemName")] = path
	return items


# One vanilla source is a plain default; several are keyed by the race prefix before "tier".
def conversion_for(sources, errors, target):
	if len(sources) == 1:
		return [("default", sources[0])]
	table = []
	for name in sources:
		race = name[:name.index("tier")]
		if not race or race in [k for k, v in table]:
			errors.append("%s: can't key %s by race" % (target, name))
			return None
		table.append((race, name))
	human = [v for k, v in table if k == "human"]
	if not human:
		errors.append("%s: no human source for default" % target)
		return None
	return [("default", human[0])] + table


def load_json_text(text):
	import tempfile
	with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False, suffix=".json") as f:
		f.write(text)
	try:
		return load_json(f.name)
	finally:
		os.remove(f.name)



def main():
	entries = json.load(open(CENSUS, encoding="utf-8"))
	items = mod_items()

	sources = {}
	for e in entries:
		if e["target"]:
			sources.setdefault(e["target"], []).append(e["itemName"])

	writes, skipped, errors = [], [], []
	for target, names in sorted(sources.items()):
		path = items.get(target)
		if not path:
			errors.append("%s: no nicemice item" % target)
			continue
		text = open(path, encoding="utf-8", newline="").read()
		if KEY in load_json(path):
			skipped.append(os.path.relpath(path, MOD).replace(os.sep, "/"))
			continue
		table = conversion_for(names, errors, target)
		if table is None:
			continue
		anchors = list(ANCHOR.finditer(text))
		if len(anchors) != 1:
			errors.append("%s: %d tooltipKind anchors" % (target, len(anchors)))
			continue
		eol = "\r\n" if "\r\n" in text else "\n"
		rows = [",%s" % eol if i else "" for i in range(len(table))]
		body = "".join("%s\t\t\"%s\" : \"%s\"" % (sep, k, v) for sep, (k, v) in zip(rows, table))
		block = "%s\t\"%s\" :%s\t{%s%s%s\t},%s" % (eol, KEY, eol, eol, body, eol, eol)
		cut = anchors[0].end()
		result = text[:cut] + block + text[cut:]
		try:
			load_json_text(result)
		except Exception as e:
			errors.append("%s: result doesn't parse: %s" % (target, e))
			continue
		writes.append((path, result, table))

	if errors:
		print("nothing written:")
		for line in errors:
			print("  " + line)
		sys.exit(1)

	for path, result, table in writes:
		with open(path, "w", encoding="utf-8", newline="") as f:
			f.write(result)
		print("wrote %s" % os.path.relpath(path, MOD).replace(os.sep, "/"))
		for k, v in table:
			print("  %-10s %s" % (k, v))

	if skipped:
		print("\nalready has %s, left alone:" % KEY)
		for line in skipped:
			print("  " + line)
	print("\n%d written, %d already present" % (len(writes), len(skipped)))


if __name__ == "__main__":
	main()
