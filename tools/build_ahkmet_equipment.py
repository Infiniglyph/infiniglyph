"""Native B8 keepsakes; reuse existing staff/sword recipes and cosmetic slots."""
import copy
import json
from pathlib import Path

DATA = Path(__file__).resolve().parents[1] / "data" / "equipment"
sources = json.loads((DATA / "pyramid_depth_equipment.json").read_text())["items"]
sources += json.loads((DATA / "pyramid_equipment.json").read_text())["items"]
items = []
for key, title, template, description in [
    ("ahkmets_scepter", "Ahkmet's Scepter", "thothic_scepter", "A staff of solidified golden light, carried by Ahkmet upon the head of the serpent he raised. When he opened his arms for the final union, Lorai received the same light. Why the Pharaoh was imprisoned remains unknown."),
    ("lorais_fangblade", "Lorai's Fangblade", "warden_khopesh", "A curved blade shaped after the fangs of Lorai, the child of Apep raised by Ahkmet. Its edge recalls a bond freely kept, even when two forms became one.")]:
    item = copy.deepcopy(next(x for x in sources if x["id"] == template))
    item.update(id=key, name=title, description=description, rarity="Legendary", value=250,
                acquisition="Pyramid B8 / Tower Exchange / Equipment Archive")
    item["geometry"]["tint"] = "ffd051"
    if key == "ahkmets_scepter":
        item["geometry"].pop("outline", None)
        item["geometry"].update(length=2.18, serpent_focus=True, light_surface=True)
        item["motion_set"].update(tempo=1.04, leverage=1.12, stance=.31, grip=.014)
    else:
        item["geometry"]["outline"] = [[-.055,-.28],[.055,-.28],[.07,.32],[.22,.64],[.40,1.02],[.37,1.32],[.28,1.12],[.12,.86],[-.01,.57],[-.055,.26]]
        item["motion_set"].update(tempo=1.07, leverage=1.15, stance=.27, grip=.018)
    items.append(item)

for key, title, slot, renderer, text in [
    ("pharaoh_vile_nemes", "Pharaoh of the Vile — Nemes", "head", "ahkmet_head", "Royal linen and a golden serpent crest from Ahkmet's ceremonial dress. The title Vile outlived every explanation for it."),
    ("pharaoh_vile_mantle", "Pharaoh of the Vile — Mantle", "body", "ahkmet_body", "A broad gold collar over dark ceremonial folds. Lorai knew this silhouette before the player ever reached the throne."),
    ("pharaoh_vile_bracers", "Pharaoh of the Vile — Bracers", "hands", "ahkmet_hands", "Gold-edged wrappings worn by the hands that raised Lorai. Their last command was an invitation, not a chain."),
    ("pharaoh_vile_greaves", "Pharaoh of the Vile — Greaves", "legs", "ahkmet_legs", "Long hieroglyphic panels above closed ceremonial greaves. Ahkmet kept his footing upon a living companion rather than a throne."),
    ("serpent_crown_union", "Serpent Crown of Union", "head", "union_crown", "Two curling lines meet beneath a single serpent crest. A keepsake of the willing union between a Pharaoh and the serpent he raised, not a mark of dominion.")]:
    items.append(dict(id=key, name=title, description=text + " Cosmetic attire.", category="cosmetics", kind="cosmetic", family=slot, slot=slot,
                      combat_kind="none", rarity="Legendary", value=120, acquisition="Pyramid B8 / Tower Exchange / Equipment Archive",
                      geometry=dict(family=slot, renderer=renderer, tint="ffd051", bulk=.32), effects=[]))

(DATA / "ahkmet_equipment.json").write_text(json.dumps(dict(version=1, items=items), indent=2) + "\n", encoding="utf-8")
print(f"Wrote {len(items)} B8 equipment definitions")
