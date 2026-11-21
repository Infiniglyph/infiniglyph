"""Rebuild the original B3-B7 loot definitions from existing native weapon recipes."""
import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data" / "equipment"
base = json.loads((DATA / "pyramid_equipment.json").read_text(encoding="utf-8"))["items"]
catalog = json.loads((DATA / "catalog.json").read_text(encoding="utf-8"))["items"]
scribe = json.loads((DATA / "scribe_equipment.json").read_text(encoding="utf-8"))["items"][1]
items = []

def source(key):
    return next(x for x in base + catalog if x["id"] == key or x["family"] == key)

def weapon(key, name, template, floor, description, factor=1.0):
    item = copy.deepcopy(scribe if template == "scribe" else source(template))
    item.update(id=key, name=name, description=description, rarity="Rare", value=160,
                acquisition=f"Pyramid {floor} / Tower Exchange / Equipment Archive")
    item["geometry"]["tint"] = "ffd170"
    if "motion_set" in item:
        item["motion_set"].update(tempo=round(0.91 + len(items)*0.017, 4),
                                  stance=round(0.19 + len(items)*0.009, 4),
                                  grip=round(0.012 + len(items)*0.001, 4),
                                  leverage=round(1.08 + len(items)*0.021, 4))
    else:
        for sequence in item["moves"].values():
            for move in sequence:
                move["damage"] = round(move["damage"] * factor, 3)
    items.append(item)
    return item

def clothing(key, name, family, floor, description, renderer=None):
    item = dict(id=key, name=name, description=description, category="cosmetics" if family != "ring" else "misc",
                kind="cosmetic" if family != "ring" else "ring", family=family, slot=family,
                combat_kind="none", rarity="Rare" if floor in ["B6", "B7"] else "Uncommon", value=65,
                acquisition=f"Pyramid {floor} / Tower Exchange / Equipment Archive",
                geometry=dict(family=family, renderer="temple_" + (renderer or key), tint="ffd170", bulk=0.3), effects=[])
    items.append(item)

weapon("sobek_warden_khopesh", "Sobek Warden Khopesh", "greatsword", "B3",
       "A massive hooked blade carried by the flood wardens. Its dark back bears the patient weight of a river; its gold edge ends that patience.")
items[-1]["geometry"]["outline"] = [[-.06,-.35],[.06,-.35],[.07,.35],[.25,.65],[.48,.98],[.54,1.40],[.37,1.67],[.46,1.36],[.29,1.11],[.05,.89],[-.07,.45]]
clothing("crocodile_cuirass", "Crocodile Warden Cuirass", "body", "B3", "Overlapping scales and river-blue seams from the wardens of the flooded halls. Every plate suggests a patience that can become violence.")
clothing("floodguard_tassets", "Floodguard Tassets", "legs", "B3", "Layered cloth, scaled greaves and a sash of water glyphs. The flood guard kept its footing when the old channels overflowed.")
clothing("sobek_emblem", "Sobek's Emblem", "ring", "B3", "A small river-warden emblem, worn smooth at its edges. A cosmetic token of the flood chambers.")
codex = weapon("scribes_grimoire", "Scribe's Grimoire", "scribe", "B4", "An archive codex recovered from an Ibis Scribe. Its golden pages preserve temple records in hieroglyphs; a cyan-tipped quill writes ankhs, eyes, reeds and river marks into the air.", .8)
codex["geometry"]["writing_system"] = "hieroglyphic"
names = ["Reed Inscription", "Crossing of the Eye", "River Edict", "Lotus Seal", "Final Cartouche", "Tablet of the Archive", "River Closure", "Warding Reeds", "Circle of the Eye"]
symbols = [[4,0,1], [1,0,5], [3,4,0], [2,0,1], [0,1,5], [4,0,1], [3,2,0], [4,0,4], [1,0,5]]
for action, sequence in codex["moves"].items():
    offset = {"attack_right":0, "attack_left":4, "special_x":5, "special_y":6, "special_rt_x":7, "special_rt_y":8}[action.removesuffix("_air")]
    for i, move in enumerate(sequence):
        move.pop("equation", None)
        move.update(writing_system="hieroglyphic", inscription=symbols[offset+i], name=names[offset+i])
scepter = weapon("thothic_scepter", "Thothic Scepter", "staff", "B4", "A ceremonial wand of the Ibis archive, crowned with a listening eye. Its keeper measured every interruption before answering it.")
scepter.update(family="wand", combat_kind="wand", guard=.55)
scepter["geometry"] = dict(family="wand", length=.74, tint="ffd170", motif="eye")
clothing("ibis_scribe_robes", "Ibis Scribe Robes", "body", "B4", "Gold-edged ceremonial robes with a turquoise collar and inscribed hanging panels. Knowledge survives here because someone still guards the shelves.")
clothing("glyphweaver_sash", "Glyphweaver Sash", "legs", "B4", "An ordered cascade of linen and knowledge glyphs, with fitted temple greaves. The archive's scribes read its markings while they walked.")
clothing("thoths_quill", "Thoth's Quill", "ring", "B4", "A feather-shaped archive keepsake. A cosmetic charm of recording and remembrance.")
clothing("mummified_wraps", "Mummified Wraps", "body", "B5", "Aged linen wound over a burial defender's frame. Faded gold stitches still hold the bandages in the shape of someone who once stood watch.")
clothing("burial_sash", "Burial Sash", "legs", "B5", "Frayed cloth with faded funerary marks and closed burial greaves. The last thread refuses to come loose.")
clothing("tomb_charm", "Tomb Charm", "ring", "B5", "A small funerary knot recovered from the restless dead. Its purpose is remembered by its wear, rather than by any remaining inscription. Cosmetic.")
weapon("sekhmet_blades", "Sekhmet's Blades", "horuswing_blades", "B6", "Swift paired blades borne by Renu and Tefet. One hunter closes the distance; one dancer makes that distance impossible to judge.")
items[-1]["geometry"]["outline"] = [[-.04,-.17],[.04,-.17],[.05,.18],[.14,.43],[.28,.67],[.32,.94],[.24,.81],[.10,.63],[-.01,.39],[-.04,.15]]
weapon("champions_spear", "Champion's Spear", "sentinel_spear", "B6", "Sakhra's ceremonial spear. Its wide, deliberate sweeps hold room for her sisters to move, until there is no room left for anyone else.")
items[-1]["geometry"]["length"] = 2.12
clothing("lioness_champion_armor", "Lioness Champion Armor", "body", "B6", "Battle attire of the three lioness champions. A gold collar joins layered plates, carrying the marks of the huntress, the dancer and the warden.")
clothing("champion_tassets", "Champion's Tassets", "legs", "B6", "Flowing temple cloth above fitted gold greaves. Three lioness marks honor a battle fought together.")
clothing("sekhmet_sigil", "Sekhmet's Sigil", "ring", "B6", "A mark awarded only when all three champions have fallen. Its three tiny seams meet in a single unbroken circle. Cosmetic keepsake.")
weapon("charmers_whip", "Charmer's Whip", "whip", "B7", "A flexible ritual lash recovered from an undead snake charmer. Its gold segments carry the rhythm once answered by a hundred restless coils.")
clothing("serpent_cultist_hood", "Serpent Cultist Hood", "head", "B7", "A tattered headdress with a narrow gold crown and falling serpent-marked cloth. Its folds conceal the face that once gave the pit its commands.")
clothing("cultist_wraps", "Cultist Wraps", "body", "B7", "Ritual linen crossed by serpent glyphs. Even empty, the wrappings seem arranged around a breath waiting to be taken.")
clothing("viperbinding_sash", "Viperbinding Sash", "legs", "B7", "Long layered cloth and closed greaves, adorned with the marks of coiled serpents. The charms are silent now.")
clothing("serpent_idol", "Serpent Idol", "ring", "B7", "A tiny coiled-serpent charm from the deepest occupied pit. The gold is warm, but the eyes offer no command. Cosmetic.")

destination = DATA / "pyramid_depth_equipment.json"
destination.write_text(json.dumps(dict(version=1, items=items), indent=2) + "\n", encoding="utf-8")
print(f"Wrote {len(items)} original B3-B7 equipment definitions")
