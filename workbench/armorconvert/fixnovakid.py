#!/usr/bin/env python3
# Run from anywhere: python3 workbench/armorconvert/fixnovakid.py
import os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from census import load_json
from buildreverse import load_json_text, KEY, MOD

ARMORS = os.path.join(MOD, "items", "armors", "nicemice")

VALUE = re.compile(r'"novakid(tier\d[ams]?(?:head|chest|pants))"')
RACEKEY = re.compile(r'"nova"(\s*:)')


def main():
	writes, errors = [], []
	for root, dirs, files in os.walk(ARMORS):
		for name in sorted(files):
			if os.path.splitext(name)[1] not in (".head", ".chest", ".legs", ".back"):
				continue
			path = os.path.join(root, name)
			rel = os.path.relpath(path, MOD).replace(os.sep, "/")
			if KEY not in load_json(path):
				continue
			text = open(path, encoding="utf-8", newline="").read()
			result, values = VALUE.subn(r'"nova\1"', text)
			result, keys = RACEKEY.subn(r'"novakid"\1', result)
			if not values and not keys:
				continue
			try:
				table = load_json_text(result).get(KEY, {})
			except Exception as e:
				errors.append("%s: result doesn't parse: %s" % (rel, e))
				continue
			if "nova" in table or any(v.startswith("novakidtier") for v in table.values()):
				errors.append("%s: still wrong after rewrite" % rel)
				continue
			writes.append((path, rel, result, values, keys))

	if errors:
		print("nothing written:")
		for line in errors:
			print("  " + line)
		sys.exit(1)

	for path, rel, result, values, keys in writes:
		with open(path, "w", encoding="utf-8", newline="") as f:
			f.write(result)
		print("%s (%d values, %d keys)" % (rel, values, keys))

	print("\n%d files fixed" % len(writes))


if __name__ == "__main__":
	main()
