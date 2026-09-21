#!/usr/bin/env python3
# Run from anywhere: python3 workbench/descriptions/census.py <unpacked assets folder>
import argparse, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.normpath(os.path.join(HERE, "..", ".."))
CENSUS = os.path.join(HERE, "census.json")

EXTENSIONS = (".object", ".material")
KEY = "nicemiceDescription"


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


def patch_adds_key(ops):
	for op in ops:
		if isinstance(op, list):
			if patch_adds_key(op):
				return True
		elif isinstance(op, dict) and op.get("op") in ("add", "replace") and op.get("path") == "/" + KEY:
			return True
	return False


def covered_by_mod(rel):
	patch = os.path.join(MOD, rel + ".patch")
	if os.path.isfile(patch) and patch_adds_key(load_json(patch)):
		return True
	override = os.path.join(MOD, rel)
	return os.path.isfile(override) and KEY in load_json(override)


def main():
	parser = argparse.ArgumentParser()
	parser.add_argument("assets")
	args = parser.parse_args()
	root = os.path.abspath(args.assets)
	if not os.path.isdir(root):
		sys.exit("not a folder: %s" % root)

	missing, errors, unscannable = [], [], []
	counts = {ext: {"total": 0, "covered": 0} for ext in EXTENSIONS}
	for dirpath, dirnames, filenames in os.walk(root):
		dirnames.sort()
		for name in sorted(filenames):
			ext = os.path.splitext(name)[1]
			if ext not in EXTENSIONS:
				continue
			path = os.path.join(dirpath, name)
			rel = os.path.relpath(path, root).replace(os.sep, "/")
			try:
				data = load_json(path)
				done = KEY in data or covered_by_mod(rel)
			except Exception as e:
				errors.append({"file": rel, "error": str(e)})
				continue
			if data.get("scannable") is False:
				unscannable.append(rel)
				continue
			counts[ext]["total"] += 1
			if done:
				counts[ext]["covered"] += 1
				continue
			missing.append(
			{
				"file": rel,
				"shortdescription": data.get("shortdescription"),
				"description": data.get("description"),
				"racial": {k: v for k, v in data.items() if k.endswith("Description")}
			})

	with open(CENSUS, "w", encoding="utf-8", newline="\n") as f:
		json.dump({"assets": root, "mod": MOD, "counts": counts, "missing": missing, "errors": errors}, f, indent="\t", ensure_ascii=False)
		f.write("\n")

	for ext in EXTENSIONS:
		c = counts[ext]
		print("%-10s %5d total  %5d covered  %5d missing" % (ext, c["total"], c["covered"], c["total"] - c["covered"]))
	print("%d unreadable" % len(errors))
	print("%d unscannable, skipped" % len(unscannable))
	print("wrote %s" % CENSUS)


main()
