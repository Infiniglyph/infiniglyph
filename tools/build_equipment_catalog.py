"""Build original equipment definitions from the user's local reference lists.

Reads references in place. No source portraits, HKX files, names or descriptions
are shipped. The private crosswalk/audit is written under ignored .godot/.
Run: python tools/build_equipment_catalog.py --references <Downloads directory>
"""
import argparse
import collections
import csv
import hashlib
import json
import math
import pathlib
import re
import unicodedata
import zipfile
import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[1]
ARCHIVES = {"weapons":"01_weapons-20261112T232234Z-1-001.zip", "shields":"02_shields-20261112T232519Z-1-001.zip", "armor":"03_armor-20261112T232308Z-1-001.zip", "rings":"05_rings-20261112T232504Z-1-001.zip"}
AFFIXES = ["Heavy","Sharp","Refined","Simple","Crystal","Fire","Chaos","Lightning","Deep","Dark","Poison","Blood","Raw","Blessed","Hollow"]
WEAVES = ["Anchor","Edge","Concord","Quiet","Prism","Ember","Fractal","Arc","Depth","Void","Verdant","Ruby","Plain","Halo","Echo"]
PALETTE = ["75eaff","bc9aff","ffb957","89ffd5","ff7ab3","81aaff","eafcff","ff7459"]
ADJECTIVES = ["Unwritten","Civic","Hollow-Signal","Luminous","Patient","Quiet","Wayward","Braided","Lucent","Distant","Folded","Returning","Prismatic","Sleepless","Measured","Kindled","Tessellated","Remembered","Wandering","Open","Unbroken","Resonant","Indexed","Unbound"]
SUBJECTS = ["Accord","Promise","Interval","Witness","Proof","Hearth","Transit","Argument","Lattice","Echo","Threshold","Margin","Relay","Contour","Meridian","Parallax","Circuit","Lantern","Chorus","Vector","Trace","Aperture","Recursion","Horizon"]
NOUNS = {"dagger":"Knife","sword":"Edge","greatsword":"Greatblade","curved_sword":"Crescent","katana":"Longcurve","twin_blades":"Paired Edges","axe":"Splitter","hammer":"Maul","spear":"Lance","halberd":"Glaive","scythe":"Reaper","fist":"Knuckles","whip":"Filament","bow":"Arcframe","crossbow":"Boltframe","staff":"Conduit","chime":"Resonator","talisman":"Focus","shield":"Aegis","head":"Crown","body":"Vestment","hands":"Grips","legs":"Greaves","ring":"Loop"}
ALIASES = {"Astora Sword":"Astora Straight Sword","Barbed Sword":"Barbed Straight Sword","Blue Shield":"Blue Wooden Shield","Caduceus Shield":"Caduceus Round Shield","Carthus Greatsword":"Carthus Curved Greatsword","Carthus Sword":"Carthus Curved Sword","Cathedral Greatshield":"Cathedral Knight Greatshield","Cathedral Greatsword":"Cathedral Knight Greatsword","Corvian Scythe":"Great Corvian Scythe","Dark Sword":"Reinforced Dark Sword","Demon Scar":"Demon's Scar","Eagle Kite Shield":"Silver Eagle Kite Shield","Eastern Shield":"Eastern Iron Shield","Elkhorn Shield":"Elkhorn Round Shield","Falcon Shield":"Golden Falcon Shield","Followers Shield":"Follower Shield","Gael Greatsword":"Gael's Greatsword","Great Door Twinshields":"Giant Door Shield","Herald Curved Greatsword":"Harald Curved Greatsword","Iron Shield":"Iron Round Shield","Lothric Greatshield":"Lothric Knight Greatshield","Lothric Greatsword":"Lothric Knight Greatsword","Lothric Long Spear":"Lothric Knight Long Spear","Lothric Shield":"Lothric Knight Shield","Lothric Sword":"Lothric Knight Sword","Painting Guardian's Sword":"Painting Guardian's Curved Sword","Red Halberd":"Red Hilted Halberd","Red and White Shield":"Red and White Round Shield","Rotten Ghru Sword":"Rotten Ghru Curved Sword","Serpent Hatchet":"Man Serpent Hatchet","Wargod Shield":"Wargod Wooden Shield","Warrior's Shield":"Warrior's Round Shield","White Tree Bow":"White Birch Bow","Wooden Hammer":"Great Wooden Hammer"}
STORIES = [
 "Its maker left the final line unfinished so another mind could answer.",
 "Passed from hand to hand, it remembers agreements more carefully than victories.",
 "A small inscription beneath the grip reads: a borrowed purpose is still a choice.",
 "Its light was tuned for travelers returning through streets that no longer felt familiar.",
 "The surface carries a repair signed by someone who refused to discard a useful thing.",
 "Made for a bearer who valued a clear question above a comfortable answer.",
 "Its owner counted the names of companions along this lattice, leaving room for more.",
 "A disputed maker's mark survives inside. Neither claimant wished the other erased.",
 "The repeating lines never quite meet. Their author called that space an invitation.",
 "A familiar pattern, altered by many hands until no two remember it the same way.",
 "The bearer who first marked it kept a place at the table for an unexpected guest.",
 "It was repaired with a different color of light; the seam became its proudest feature."]

def portrait_shape(data, fam, length, name):
    """Coarse proportions/cross-sections, not source pixels or texture contours.

    Principal axis removes the portrait's presentation tilt. Twenty-five cross
    sections keep characteristic wide heads, curves and asymmetric blades.
    Armor is fitted in 3D to each joint, rather than extruded as a flat panel.
    """
    im=np.asarray(Image.open(data).convert('RGBA'))
    ys,xs=np.nonzero((im[:,:,3]>225)&(im[:,:,:3].max(axis=2)>28))
    if len(xs)<30:return {}
    xy=np.column_stack((xs,ys)).astype(float);xy-=xy.mean(axis=0)
    _,vectors=np.linalg.eigh(np.cov(xy.T));axis=vectors[:,-1]
    if axis[1]<0:axis=-axis
    # Portrait blades usually hang point-down; pole/impact heads are point-up.
    # Orient the handle toward the grip origin instead of holding a spearhead.
    head_up=fam in ['spear','halberd','scythe','axe','hammer']
    if fam=='axe' and any(word in name.lower() for word in ['machete','knife']):head_up=False
    if fam=='dagger' and any(word in name.lower() for word in ['harpe','hand scythe','candlestick']):head_up=True
    if head_up:axis=-axis
    along=xy@axis;across=xy@np.array([axis[1],-axis[0]])
    lo,hi=np.quantile(along,[.005,.995]);extent=max(1,hi-lo)
    bulk=float(np.quantile(across,.98)-np.quantile(across,.02))/extent
    result={'bulk':round(bulk,3)}
    if fam in ['head','body','hands','legs','ring','bow','crossbow','talisman','chime','fist','whip']:return result
    sections=[]
    for i in range(25):
        t=(i+.5)/25;band=np.abs((along-lo)/extent-t)<1/50
        if band.sum()<3:continue
        left,right=np.quantile(across[band],[.04,.96]);sections.append((t,left/extent,right/extent))
    if len(sections)<4:return result
    # The outline remains deliberately low-detail; authored neon inlays and
    # thickness make a new solid object instead of a source-image billboard.
    outline=[(round(l*length,4),round((t-.18)*length/.82,4)) for t,l,r in sections]
    outline += [(round(r*length,4),round((t-.18)*length/.82,4)) for t,l,r in reversed(sections)]
    if fam=='shield':outline=[(round(x/length*.85,4),round(y/length*.85-.25,4)) for x,y in outline]
    result['outline']=outline
    return result

def normal(text):
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9+]", "", text.lower())

def seed(text): return int(hashlib.sha256(text.encode()).hexdigest()[:12], 16)

def family(name, category):
    n = name.lower()
    if category == "rings": return "ring"
    if category == "armor":
        if any(k in n for k in ["gauntlet","glove","bracelet","wraps","manchette","grip"]): return "hands"
        if any(k in n for k in ["legging","trouser","skirt","loincloth","boots"]): return "legs"
        if any(k in n for k in ["helm","hood","crown","mask","hat","head","blindfold","veil","wrappings"]): return "head"
        return "body"
    if any(k in n for k in ["crossbow","arbalest","avelyn"]): return "crossbow"
    if category == "shields" or any(k in n for k in ["shield","buckler","parma"]): return "shield"
    if "bow" in n: return "bow"
    if any(k in n for k in ["twin","paired","onikiri","dancer's","crow quills","valorheart","drang"]): return "twin_blades"
    if any(k in n for k in ["uchigatana","washing pole","chaos blade","black blade","bloodlust","darkdrift","frayed blade"]): return "katana"
    if any(k in n for k in ["scythe"]): return "dagger" if "hand" in n else "scythe"
    if any(k in n for k in ["halberd","glaive","lucerne","splitleaf","crucifix","immolation tinder"]): return "halberd"
    if any(k in n for k in ["spear","lance","partizan","plow","bident","javelin","war banner","soldering"]) or re.search(r'\bpike\b',n): return "spear"
    if any(k in n for k in ["whip","locks","rose of"]): return "whip"
    if any(k in n for k in ["staff","branch","preacher"]): return "staff"
    if any(k in n for k in ["chime","bellvine"]): return "chime"
    if any(k in n for k in ["talisman","pyromanc"]): return "talisman"
    if any(k in n for k in ["claw","caestus","fist","dark hand","talons"]): return "fist"
    if any(k in n for k in ["axe","hatchet","eleonora","earth seeker","machete","butcher"]): return "axe"
    if any(k in n for k in ["hammer","club","mace","morning star","pick","dragon tooth"]): return "hammer"
    if any(k in n for k in ["dagger","knife","harpe","mail breaker","short sword","scholar's candlestick"]): return "dagger"
    if any(k in n for k in ["greatsword","zweihander","claymore","bastard","flamberge","storm ruler","murakumo"]): return "greatsword"
    if any(k in n for k in ["curved","shotel","scimitar","falchion","sabre","crescent moon","demon's scar"]): return "curved_sword"
    return "sword"

def base_name(name, known):
    for index,prefix in enumerate(AFFIXES+["Skilled","Simpleton"]):
        candidate=re.sub(r'(?<!\S)'+prefix+r'(?!\S)\s*','',name).strip()
        if candidate!=name and normal(candidate) in known:
            return candidate, WEAVES[index] if index<len(WEAVES) else 'Concord'
    match = re.search(r"\s*\+(\d+)$", name)
    return (name[:match.start()], "Mark "+match[1]) if match else (name, "")

def geometry(fam, s, name=""):
    length = {"dagger":.64,"sword":1.18,"greatsword":1.7,"curved_sword":1.12,"katana":1.3,"twin_blades":.82,"axe":1.05,"hammer":1.15,"spear":2.35,"halberd":2.05,"scythe":2.0,"fist":.26,"whip":1.65,"bow":1.4,"crossbow":.8,"staff":1.9,"chime":.5,"talisman":.4,"shield":.9}.get(fam, .8)
    if any(k in name.lower() for k in ["great","large","ultra","lance","pike"]): length *= 1.15
    if "short" in name.lower(): length *= .78
    return {"family":fam,"length":round(length*(.94+(s%13)*.01),3),"width":round(.08+((s//13)%10)*.009,3),"depth":.24 if fam=='hammer' else (.13 if fam=='axe' else (.09 if fam=='shield' else .05)),"curve":round(.08+((s//127)%8)*.025,3) if fam in ["katana","curved_sword","scythe"] else 0,"guard":round(.2+((s//19)%10)*.024,3),"detail":s%7,"paired":fam=="twin_blades","tint":PALETTE[s%len(PALETTE)]}

def motion_frames(style, index, air=False):
    frames=[]
    for t in [0,.18,.42,.68,1]:
        u=math.sin(t*math.pi); sign=1 if index%2==0 else -1
        if style=="moon":
            a=(t*1.6-.55+index*.22)*math.pi*sign
            r=[.24*math.cos(a),1.21+.31*math.sin(a),.24+.12*u]
            l=[r[0]-.08,r[1]-.12,r[2]-.02]; rr=[1.4*u+.1,a*.45,sign*(t*2.7-1.2)]
            hip=[.1*u,sign*(t*2-1)*.8*u,.04*sign*u]
        elif style=="horizon":
            r=[.22*sign,1.13+u*.12,.12+.41*math.sin(math.pi*min(1,t*1.6))]
            l=[-.06*sign,1.24,.24+.18*u];rr=[1.57,.1*sign,(-.32+.25*u)*sign]
            hip=[.23*u,sign*(-.55+.85*u)*u,-.08*u]
        else:
            a=(t*(2+index*.25)+index*.18)*math.pi
            r=[.33*math.cos(a),1.22+.22*math.sin(a),.26+.1*u]
            l=[-.33*math.cos(a+.6),1.23-.22*math.sin(a+.6),.26+.12*u]
            rr=[.8*u,a*.45,1.1*math.sin(a)];hip=[.14*u,math.sin(a)*.7,.10*math.cos(a)*u]
        if air:r[1]+=.13*u; l[1]+=.1*u; hip[0]-=.22*u
        frames.append({"t":t,"right":[round(x,4) for x in r],"left":[round(x,4) for x in l],"right_rotation":[round(x,4) for x in rr],"left_rotation":[round(rr[0]*.8,4),round(-rr[1],4),round(-rr[2],4)],"hip":[round(x,4) for x in hip],"chest":[round(-hip[0]*.5,4),round(-hip[1]*.3,4),round(-hip[2]*.5,4)]})
    return frames

def attack(title, duration, reach, profile, side, style, index, air=False, hits=None):
    return {"name":title,"duration":duration,"windup":round(duration*.26,3),"damage":20 if style=="moon" else (23 if style=="horizon" else 15),"reach":reach,"arc":46 if profile in ["thrust","beam","spiral"] else 125,"profile":profile,"hits":hits or [round(duration*.42,3)],"side":side,"parryable":True,"hit_stun_level":1.0,"hit_stagger":.24,"body_profile":{"moon":[.12,.85,.26,.2,.13],"horizon":[.15,.4,.32,.18,.2],"argument":[.10,.72,.22,.21,.09]}[style],"motion":motion_frames(style,index,air)}

def named_items():
    result=[]
    entries=[("fractured_moon","The Fractured Moon","katana","right","moon",2.25,"A curved lattice divided by deliberate gaps. Its maker believed a conclusion should leave room to turn. The crescent returns by another path, and the airborne cut finishes a different sentence."), ("event_horizon","Event Horizon","spear","left","horizon",3.2,"A long, narrow spear with a suspended ring around its point. A courier marked each uninterrupted journey along its haft. The inscriptions celebrate arrival, never the distance another mind was pushed aside."), ("last_argument","The Last Argument","twin_blades","up","argument",1.8,"Two unequal edges passed between companions who could agree on almost nothing. One cut opens a question; the other answers from an unexpected angle. Neither blade carries the word final.")]
    titles={"moon":["Unclosed Circle","Returning Crescent","Broken Orbit","Moonward Turn"],"horizon":["Approach Vector","Needle Transit","Vanishing Point","Long Arrival"],"argument":["First Objection","Counterpoint","Cross Examination","Unfinished Reply"]}
    profiles={"moon":["crescent","cross","waltz","orbit"],"horizon":["thrust","spiral","beam","pillar"],"argument":["cross","lattice","waltz","comets"]}
    for iid,title,fam,slot,style,reach,lore in entries:
        s=seed(iid);g=geometry(fam,s);g.update({"length":{"moon":1.32,"horizon":2.5,"argument":.8}[style],"width":{"moon":.042,"horizon":.065,"argument":.052}[style],"tint":{"moon":"bc9aff","horizon":"75eaff","argument":"ff7ab3"}[style],"segmented":style=="moon","ring_head":style=="horizon","asymmetric":style=="argument"})
        moves={}
        for airborne in [False,True]:
            for side,action in [(-1,"attack_left"),(1,"attack_right")]:
                key=action+("_air" if airborne else "")
                moves[key]=[attack(titles[style][i]+(" / Sky" if airborne else ""),round(({"moon":.5,"horizon":.6,"argument":.34}[style])+i*.055+(0.04 if airborne else 0),3),reach+i*.12,profiles[style][i%3],side,style,i+(3 if side<0 else 0),airborne) for i in range(3)]
            for i,action in enumerate(["special_x","special_y","special_rt_x","special_rt_y"]):
                duration=.78+i*.12; hits=[round(duration*.4,3)] if i%2==0 else [round(duration*.36,3),round(duration*.64,3)]
                moves[action+("_air" if airborne else "")]=[attack(titles[style][i]+(" / Sky Art" if airborne else " / Art"),duration,reach+1+i*.4,profiles[style][i],1,style,i+6,airborne,hits)]
        result.append({"id":iid,"name":title,"description":lore,"category":"weapons","kind":"named","family":fam,"slot":slot,"combat_kind":fam,"rarity":"Named","value":180,"acquisition":"Tower Exchange / named designs","geometry":g,"moves":moves,"effects":[],"attachment":{"primary_hand":"right","offhand":"left" if fam=='twin_blades' else 'support',"stow":"left_hip" if fam=='katana' else 'back',"model_axis":"+Y"}})
    return result

def main():
    parser=argparse.ArgumentParser();parser.add_argument("--references",type=pathlib.Path,required=True);args=parser.parse_args()
    rows=[];portraits={};audit={"archives":[],"crosswalk":[]}
    for category,filename in ARCHIVES.items():
        with zipfile.ZipFile(args.references/filename) as z:
            names=sorted(n for n in z.namelist() if n.lower().endswith('.png'))
            audit['archives'].append({"archive":filename,"portraits":len(names)})
            for path in names:
                stem=pathlib.PurePosixPath(path).stem;code,label=stem.split(' - ',1)
                name=label.replace('_s',"'s").replace('_',"'")
                key=(category,normal(name));previous=portraits.get(key,{})
                portraits[key]={"name":name,"archive":filename,"path":path,"alternate_paths":previous.get('alternate_paths',[])+[path],"code":code.rsplit('_',1)[-1]}
    for category,filename in [("weapons","weapons.csv"),("armor","armor.csv"),("rings","rings.csv")]:
        with (args.references/filename).open(encoding='utf-8-sig',newline='') as f:
            for row in csv.DictReader(f):
                row={k.strip():v.strip() for k,v in row.items()};rows.append({"name":row['NAME'],"code":row['HEX'].lower(),"category":category,"csv":filename})
    source_rows=len(rows)
    known={normal(r['name']) for r in rows}|{key[1] for key in portraits}|{normal(k) for k in ALIASES}
    aliases={normal(k):normal(v) for k,v in ALIASES.items()}
    used=set();items=[];names=set();families=collections.Counter();shape_cache={};archives={}
    for row in rows:
        base,weave=base_name(row['name'],known);cat=row['category'];fam=family(base,cat)
        pc='shields' if fam=='shield' else cat
        lookup=aliases.get(normal(base),normal(base))
        portrait=portraits.get((pc,lookup)) or portraits.get(('weapons',lookup))
        if portrait:
            used.add((pc,lookup))
            used.add(('weapons',lookup))
        row.update(base=base,weave=weave,family=fam,portrait=portrait)
    # Portrait-only DLC/alternate pieces get their own counterparts as well.
    for key,p in portraits.items():
        if key not in used:
            rows.append({"name":p['name'],"base":p['name'],"weave":"","code":"portrait_"+p['code'],"category":key[0],"family":family(p['name'],key[0]),"portrait":p})
    for row in rows:
        cat=row['category'];fam=row['family'];s=seed(row['base']);iid='eq_'+{'weapons':'w','shields':'s','armor':'a','rings':'r'}[cat]+'_'+row['code']
        title=ADJECTIVES[s%24]+' '+SUBJECTS[(s//24)%24]+' '+NOUNS[fam]
        if row['weave']:title+=' / '+row['weave']
        if title in names:title+=' '+str(seed(iid)%10000).zfill(4)
        names.add(title);families[fam]+=1
        first=s%len(STORIES);second=(s//13+5)%len(STORIES)
        if second==first:second=(second+1)%len(STORIES)
        lore=STORIES[first]+' '+STORIES[second]
        cosmetic=fam in ['head','body','hands','legs','shield'];category='cosmetics' if cosmetic else ('misc' if fam=='ring' else 'weapons')
        kind='standard' if category=='weapons' else ('ring' if fam=='ring' else 'cosmetic')
        slot={'katana':'right','twin_blades':'up','fist':'up','spear':'left','halberd':'left','scythe':'left','staff':'left'}.get(fam,'down') if category=='weapons' else fam
        combat='katana' if fam=='katana' else ('twin_blades' if fam in ['twin_blades','fist'] else ('spear' if fam in ['spear','halberd','scythe','staff'] else 'sword_shield'))
        g=geometry(fam,s,row['base']);g['style']='cloth' if any(x in row['base'].lower() for x in ['robe','dress','garb','cloth','hood','attire','skirt']) else 'plate'
        if fam=='head':g['head_form']=next((word for word in ['crown','mask','hat','hood','blindfold'] if word in row['base'].lower()),'helmet')
        if any(word in row['base'].lower() for word in ['rapier','estoc','mail breaker']):g['attack_style']='thrust'
        if row.get('portrait'):
            p=row['portrait'];key=p['path']
            if key not in shape_cache:
                if p['archive'] not in archives:archives[p['archive']]=zipfile.ZipFile(args.references/p['archive'])
                with archives[p['archive']].open(key) as image:shape_cache[key]=portrait_shape(image,fam,g['length'],row['base'])
            g.update(shape_cache[key])
        item={"id":iid,"name":title,"description":lore+(" Cosmetic; no defensive or movement bonuses." if cosmetic else (" A keepsake; no gameplay effect is configured." if fam=='ring' else "")),"category":category,"kind":kind,"family":fam,"slot":slot,"combat_kind":combat,"rarity":"Crafted","value":35+(s%10)*5,"acquisition":"Tower Exchange / reference counterparts","geometry":g,"effects":[]}
        items.append(item);audit['crosswalk'].append({"source":row['name'],"source_id":row['code'],"csv":row.get('csv'),"portrait":row.get('portrait'),"item_id":iid,"name":title,"family":fam})
    animation=args.references/'DAR - Dark Souls Animated Armoury for ABR-103155-1-0-0-1702946612.zip'
    with zipfile.ZipFile(animation) as z:
        hkx=[n for n in z.namelist() if n.lower().endswith('.hkx')]
        audit['animation']={"archive":animation.name,"hkx_count":len(hkx),"families":dict(collections.Counter(pathlib.PurePosixPath(n).name.lower().split('_')[0] for n in hkx)),"clips":dict(collections.Counter(pathlib.PurePosixPath(n).name.lower() for n in hkx)),"conditions":[{"path":n,"text":z.read(n).decode('utf-8-sig',errors='replace')} for n in z.namelist() if n.lower().endswith('_conditions.txt')]}
    data=ROOT/'data/equipment';data.mkdir(parents=True,exist_ok=True)
    temporary=data/'catalog.json.tmp'
    temporary.write_text(json.dumps({"version":1,"items":items},ensure_ascii=False,separators=(',',':')),encoding='utf8')
    temporary.replace(data/'catalog.json')
    if not (data/'named_weapons.json').exists():
        (data/'named_weapons.json').write_text(json.dumps({"version":1,"items":named_items()},indent=2),encoding='utf8')
    private=ROOT/'.godot/equipment-references';private.mkdir(parents=True,exist_ok=True)
    audit['summary']={"counterparts":len(items),"families":dict(families),"named_demonstrations":3,"source_rows":source_rows,"portrait_only":len(items)-source_rows}
    (data/'summary.json').write_text(json.dumps(audit['summary'],indent=2),encoding='utf8')
    (private/'crosswalk.json').write_text(json.dumps(audit,indent=2),encoding='utf8')
    print(json.dumps(audit['summary'],indent=2))
    for archive in archives.values():archive.close()

if __name__=='__main__':main()
