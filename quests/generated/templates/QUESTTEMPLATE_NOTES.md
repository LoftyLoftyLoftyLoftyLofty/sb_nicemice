# Quest template dialog — handoff notes

Companion to section 12 of `NICEMICE_HANDOFF.md`. Covers `/quests/templates/`,
which is a separate surface from `/dialog/quest.config`.

## What shipped

35 patches, 206 guarded groups, 606 ops (400 `test`, 194 `add`, 12 `replace`),
309 mouse lines across 159 pools.

Path layout: `/quests/templates/<name>.questtemplate.patch`.

## Structure of the target

`scriptConfig.generatedText` routes as `fragment / [subfragment] / speaker
species / [lines]`. Vanilla ships exactly three species keys — `floran`,
`glitch`, `default`. Mice get `nicemice_npc` alongside them.

Speaker-side only. Every one of these templates carries `questGiver`, so the
species that resolves is the quest giver's, and mouse villagers, tenants and
maus types all hit it.

Subfragments in play: `first`, `next`, `last`, `default`. Not every template has
all four — `barter` has one pool per fragment; `collect_fine`, `intimidate`,
`return_stolen`, `share_secret` and `spread_rumors` have all four on both `text`
and `completionText`.

## Patch structure — every op is gated

**The top level of each file is an array of arrays.** Each inner array is one
guarded group, applied independently. A failed `test` aborts only its own group,
so a conflict on one pool cannot take down the pools after it.

This matters most on the nine-pool templates. Flat, a conflict on the first pool
silently drops the other eight and the quest comes out half-accented — which
reads as sloppy writing rather than as a patch conflict, and is therefore the
worst available failure mode. Grouped, you lose exactly the pool that conflicted.

The standard group, used for all 159 speech pools:

```
[
	{ "op" : "test", "path" : "/scriptConfig/generatedText/<route>" },
	{ "op" : "test", "path" : "/scriptConfig/generatedText/<route>/nicemice_npc", "inverse" : true },
	{ "op" : "add",  "path" : "/scriptConfig/generatedText/<route>/nicemice_npc", "value" : [ ... ] }
]
```

First test: the parent still exists (another mod may have restructured it).
Second: we are not overwriting, and not re-applying.

Nothing is added without both tests passing. There are no bare ops in the set.

## Titles — two categories, two mutually exclusive groups

23 templates carry a title, in two shapes:

**Category 2 — already nested under `/default`** (11 templates: `capture_pet`,
`escort`, `hat`, `helmet`, `kidnapping`, `kill_monster_group`,
`kill_monster_single`, `kill_npc`, `kill_npcs`, `new_stock1`, `new_stock2`).
Ordinary guarded `add` of `nicemice_npc`.

**Category 1 — a bare array** (12 templates: `add_object_to_house`, `bribe`,
`build_home`, `collect_fine`, `gift`, `intimidate`, `protect`, `recruit_guard`,
`return_stolen`, `share_secret`, `spread_rumors`, `themed_build`). There is no
species level to add into, so the node has to be split.

Every title-bearing file gets the category-2 group. The 12 category-1 files get a
second group as well:

```
[
	{ "op" : "test",    "path" : "/scriptConfig/generatedText/title", "value" : [ <exact vanilla lines> ] },
	{ "op" : "replace", "path" : "/scriptConfig/generatedText/title",
	  "value" : { "default" : [ <exact vanilla lines> ], "nicemice_npc" : [ ... ] } }
]
```

The value-test is what makes the `replace` safe. It fires only when the node is
byte-identical to stock vanilla. If another mod has rewritten the title, the test
fails, the group aborts, and their version is left completely alone — we simply
don't get mouse titles on that template.

The two groups are mutually exclusive by construction:

| starting state | cat-2 group | cat-1 group | outcome |
|---|---|---|---|
| pristine flat array | skips (no `/default`) | fires | split, vanilla preserved under `default` |
| already split by another mod | fires | skips (not a bare array) | added beside their keys |
| flat array rewritten by another mod | skips | skips (value mismatch) | untouched |
| this patch re-applied | skips (`nicemice_npc` present) | skips | no-op |

All four verified per template — see below.

## Fluff — a tag pool, not a dialog pool

`generatedText.fluff` is an array of `[tagName, [values]]` pairs feeding
`<verb1>`, `<crime>`, `<appreciation>` and friends. Not species-keyed at all.
Vanilla fakes species variants by *naming* the tag with a suffix —
`<florandreams>`, `<crimefloran>`, `<appreciationfloran>` — and referencing it
only inside floran lines.

Mice follow the Floran model: self-contained lines plus `nicemice`-prefixed fluff
appended via `/fluff/-`. Using vanilla's neutral pools would inject plain English
mid-accent.

New tags by file:

- `capture_pet` — `nicemicedreams`, `nicemiceappreciation`
- `escort` — `nicemicefriend`, `nicemiceactivity`, `nicemiceappreciation`
- `escort_trade` — `nicemiceappreciation`
- `kidnapping` — `nicemicefriend`, `nicemiceactivity`, `nicemiceappreciation`
- `kill_monster_group` — `nicemicebelonging`, `nicemicerevenge`, `nicemiceappreciation`
- `kill_monster_single` — `nicemicegiant`, `nicemicerumour`, `nicemicerequest`, `nicemiceappreciation`
- `kill_npc` — `nicemicecrime`, `nicemicerequest`, `nicemiceappreciation`
- `kill_npcs` — `nicemicecrime`, `nicemicejustice`, `nicemicerequest`, `nicemiceappreciation`

Names repeat across files; fluff is per-template, so that's fine.
`share_secret`, `spread_rumors` and `collect_fine` have fluff arrays consumed by
`secretNote` / `responseNote` / the fine-notice item rather than by
`generatedText`, so they needed no additions.

**The append guard is index-and-value based**, because `/fluff/-` is otherwise
unconditional and a double install would duplicate every pool:

```
{ "op" : "test", "path" : "/scriptConfig/generatedText/fluff/<N>", "value" : [ <tag>, [ ... ] ], "inverse" : true }
```

`N` is the index the entry lands at on a clean vanilla node. On re-application our
entry is sitting there, the inverse test fails, and the group skips. If another
mod appended first, `N` holds *their* entry, the test passes, and ours still lands
at the end.

That asymmetry is deliberate. A duplicated fluff entry is cosmetically harmless —
it slightly skews a random pick. A fluff tag that fails to land renders in-game as
a literal `<nicemicedreams>` in the middle of a finished line. So the guard is
tuned to prefer appending over skipping when the situation is ambiguous.

## Tags that must survive verbatim

Beyond the list in section 10, the dotted pronoun forms are everywhere here:
`<target.pronoun.object>`, `<target.pronoun.capitalSubject>`,
`<questGiver.pronoun.possessiveDet>`, `<enemy.pronoun.copulativePast>`,
`<victimNpcType.pronoun.subject>`, `<thief.pronoun.possessiveDet>`.

`<spawnPoint>` is always followed by `<spawnPoint.direction>` — keep the pair.
Literal `\n` appears inside `capture_pet` text lines and is preserved.

## `failureText` deliberately untouched

It reads in the player's voice ("I was unable to help `<questGiver>`") but
resolves on the *quest giver's* species. Accenting it would put a mouse accent in
a non-mouse player's quest log. The "direction matters" rule applied to a
fragment that looks speaker-side and isn't. 12 templates have it flat, 11 as a
`{default: [...]}` shell; either way it stays vanilla.

## Capitalization follows vanilla per line, not a house rule

Vanilla is internally inconsistent about title case: most titles are sentence
case, but `<questGiver>'s Home Makeover`, `<questGiver>'s Agenda`,
`Bring <target> to Justice`, `<questGiver> the Gift Giver` and `<monster> Hunter`
are title-cased. Mouse titles match whichever form the vanilla line on that
template uses, so a mouse quest sitting next to another species' quest in the
log reads as the same register rather than as a styling slip.

Two article fixes came out of the same pass:

- `kill_npc` title uses `A <enemy>`, matching vanilla. `An <enemy>` misfires on
  consonant-initial enemy names.
- `request_craft` completion says `any <item>`, which is vanilla's own dodge
  around the a/an problem on a substituted noun.

## Known plain-English leaks

Two parameters resolve outside `generatedText` and stay unaccented inside mouse
lines. Both are single words; fixing them means touching the generator.

- `<adjective>` in `hat` / `helmet` — dropping it would lose the quest's premise
- `<tag>` in `recruit_guard` / `themed_build` — furniture tag

## Verification performed

A patch simulator implementing the group-abort semantics was run against each
vanilla template:

- every parent path resolves; no `add` overwrites an existing key
- **idempotence** — second application applies zero groups and leaves the
  document byte-identical
- **conflict tolerance** — with a foreign `nicemice_npc` injected into one pool,
  exactly one group skips and every other group still lands
- **title scenarios** — all four states in the table above, per template
- every `<tag>` traced to the template's vanilla text, its parameter list, or its
  newly-added fluff
- colour codes checked against `^white; ^orange; ^green; ^cyan;`
- accent lint over all 309 mouse lines for unconverted keywords
- vowel-glide check for the shipped `owes` → `oves` class of error: `own`,
  `owns`, `town`, `know`, `how` confirmed left alone

Confirmed in-game alongside a heavily-modded quest-giver set (Denelaun): mouse
titles render from `nicemice_npc` while other species continue to draw vanilla's
line from the `default` key the split wrote back. Two mods adding species keys to
the same `generatedText` node, neither displacing the other — which is the
property the additive approach exists to preserve, and the one that cannot be
tested in isolation.

Quest text resolves at generation time, so quests already offered keep whatever
they were generated with.

## Before release — please re-run the verifier against a full unpack

12 vanilla templates dropped out of the working session partway through, so the
simulation covered 23 of 35. The uncovered ones are `add_object_to_house`,
`barter`, `bribe`, `collect_fine`, `escort`, `gift`, `intimidate`,
`kill_monster_single`, `new_stock2`, `request_craft`, `spread_rumors`,
`themed_build`.

Two constants in those files were transcribed from earlier reads rather than read
from disk at emit time:

- **flat-title value-tests** — 5 of 12 checked against disk, 0 mismatches.
  `gift` was subsequently confirmed in-game: its split fired on a live install,
  which can only happen on an exact value match. The unchecked 6 are
  `add_object_to_house`, `bribe`, `collect_fine`, `intimidate`, `spread_rumors`,
  `themed_build`.
- **fluff base indices** — 6 of 8 checked, 0 mismatches. Unchecked: `escort`
  (expects 8 existing entries), `kill_monster_single` (expects 14).

Both fail safe. A wrong title value-test means the split never fires and the
title stays English. A wrong fluff index means at worst a duplicate entry on
re-install. Neither can corrupt an asset — but both are silent, so they're worth
one confirming run.

## Open threads

- `goalText` for `kill_monster_group` / `kill_monster_single` / `escort` is a
  single line in vanilla and a single line here; repetition will be audible if
  those quest types are common. Same for `escort` / `escort_trade` completion.
- `bounty.questtemplate` and friends were not in scope, consistent with the
  `bounty.config` deferral in section 12.
