#!/usr/bin/env python3
"""Rebuild ios/PogoLens/Resources/Data/gamedata.json from pogoapi.net.

Species stats (with megas folded in as forms), typing, the CP multiplier table (extended past
the published level 45 by the game's 0.0025 per half level, anchored at the last published
value), power-up dust tiers with their levels, move names, and per-species movesets.
"""
import datetime as dt
import json
import urllib.request
from pathlib import Path

BASE = "https://pogoapi.net/api/v1/"
OUT = Path(__file__).resolve().parent.parent / "ios/PogoLens/Resources/Data/gamedata.json"


def get(name):
    req = urllib.request.Request(BASE + name + ".json", headers={"User-Agent": "pogo-lens refresh"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def main():
    stats, megas, types = get("pokemon_stats"), get("mega_pokemon"), get("pokemon_types")
    cpm_raw, dust, fast, charged, cur = get("cp_multiplier"), get("pokemon_powerup_requirements"), get("fast_moves"), get("charged_moves"), get("current_pokemon_moves")
    tmap = {(r["pokemon_id"], r["form"]): r["type"] for r in types}
    species = [{"id": s["pokemon_id"], "name": s["pokemon_name"], "form": s["form"], "atk": s["base_attack"], "def": s["base_defense"], "sta": s["base_stamina"], "types": tmap.get((s["pokemon_id"], s["form"]), [])} for s in stats]
    for m in megas:
        st = m["stats"]
        form = " ".join(m["mega_name"].replace(m["pokemon_name"], "").split()) or "Mega"
        species.append({"id": m["pokemon_id"], "name": m["pokemon_name"], "form": form, "atk": st["base_attack"], "def": st["base_defense"], "sta": st["base_stamina"], "types": m.get("type", [])})
    cpm = {float(x["level"]): float(x["multiplier"]) for x in cpm_raw}
    last = max(cpm)
    level = last + 0.5
    while level <= 55.0:
        cpm[level] = round(cpm[last] + 0.0025 * (level - last) * 2, 8)
        level += 0.5
    tiers = sorted({int(r["stardust_to_upgrade"]) for r in dust.values()})
    out = {
        "source": "pogoapi.net", "pulled": dt.date.today().isoformat(), "species": species,
        "cpm": [{"level": k, "multiplier": v} for k, v in sorted(cpm.items())],
        "dust": tiers,
        "dust_levels": {str(t): sorted(float(x["current_level"]) for x in dust.values() if int(x["stardust_to_upgrade"]) == t) for t in tiers},
        "fast_moves": sorted({m["name"] for m in fast}), "charged_moves": sorted({m["name"] for m in charged}),
        "movesets": {f"{m['pokemon_id']}-{m['form']}": {"fast": sorted(set(m.get("fast_moves", []) + m.get("elite_fast_moves", []))), "charged": sorted(set(m.get("charged_moves", []) + m.get("elite_charged_moves", [])))} for m in cur},
        "types": ["Bug", "Dark", "Dragon", "Electric", "Fairy", "Fighting", "Fire", "Flying", "Ghost", "Grass", "Ground", "Ice", "Normal", "Poison", "Psychic", "Rock", "Steel", "Water"],
    }
    OUT.write_text(json.dumps(out, separators=(",", ":")), encoding="utf-8")
    print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB, {len(species)} species/forms)")


if __name__ == "__main__":
    main()
