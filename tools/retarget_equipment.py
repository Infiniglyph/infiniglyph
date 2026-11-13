"""Offline DAR study/retarget and reference-guided tailoring pass.

The optional decoder is PyNifly's anim_skyrim module, installed privately by the
developer. It is not a runtime or distributable dependency. Source archives and
the source-name crosswalk remain outside shipped content. No source root motion
is applied to the CharacterBody. Run from this repository with --decoder PATH.
"""
import argparse, collections, hashlib, json, math, pathlib, re, sys, zipfile
import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[1]
DATA = ROOT / 'data/equipment'
# Anatomical chains recovered from the supplied 99-track clips. They are an
# explicit retarget adapter, not a claim that the archive contains a skeleton.
PARENTS = {0:-1, 4:0, 5:4, 6:5, 7:6, 8:7, 9:5, 10:9, 11:10,
           24:5, 25:24, 26:25, 27:26, 28:27, 29:28, 30:26, 31:30,
           32:31, 35:26, 36:35, 50:29, 51:32}
GROUPS = {'knife':['10001','11002'], 'edge':['10002','10048'],
          'rapier':['10019','11007','11018'], 'cleaver':['10003','10006','10045'],
          'greatblade':['10004','10005','10028','10049','10050'],
          'maul':['10007','10008','10022','10054'], 'longcurve':['10009','10042','10043'],
          'lance':['10010','11010'], 'crescent':['10011','10013','11015'],
          'glaive':['10012','10021','10030','11019'], 'reaper':['10020','11014'],
          'paired':['11001','11004','11008','10027','70030','70031','70032','70033'],
          'knuckles':['11011','11012','11013'], 'filament':['11020'],
          'conduit':['10000','10034','10024']}
# The existing bank convention is Y-up/-Z forward. Runtime weapon_motion
# converts sampled hands/grips to the figure's +Z anatomical front once.
C = np.array([[1,0,0],[0,0,1],[0,-1,0]],dtype=float)

def rotation(q):
    x,y,z,w=np.asarray(q)/max(1e-8,np.linalg.norm(q))
    return np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],
                     [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],
                     [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])

def euler(m):
    # Godot's YXZ convention; normalize equivalent angles later per curve.
    x=math.asin(max(-1,min(1,-m[1,2])))
    return np.array([x,math.atan2(m[0,2],m[2,2]),math.atan2(m[1,0],m[1,1])])

def vec(v): return [round(float(n),5) for n in v]

def sole_contacts(clip):
    if clip.get('adapter_version',1)>=2:return clip
    # Source foot tracks locate ankles, not the sole. Calibrate their grounded
    # height over the whole clip, preserving actual lifts and hip compression.
    for side in ['left','right']:
        key=side+'_foot'
        floor=min(f[key][1]+f['hip_offset'][1] for f in clip['motion'])
        for frame in clip['motion']:
            frame[key][1]=round(max(.035,min(.33,.035+frame[key][1]+frame['hip_offset'][1]-floor)),5)
    clip['adapter_version']=2
    return clip

def retarget(anim):
    if anim.num_tracks not in [97,99] or anim.duration<.16 or anim.duration>9:
        raise ValueError('unsupported source rig/duration')
    frames=[];origin=np.array(anim.tracks[4].translations[0])
    # Preserve source frame cadence up to 60 samples per clip, including ends.
    for f in np.unique(np.linspace(0,anim.num_frames-1,min(60,anim.num_frames)).round().astype(int)):
        world={}
        for i,parent in PARENTS.items():
            t=anim.tracks[i];r=rotation(t.rotations[f]);p=np.array(t.translations[f])
            world[i]=(r,p) if parent<0 else (world[parent][0]@r,world[parent][1]+world[parent][0]@p)
        hip_r,hip_p=world[5];chest_r,chest_p=world[26]
        out={'t':round(f/(anim.num_frames-1),6)}
        # Our shoulder and chain lengths replace the source anatomy. The arm
        # directions retain the source shoulder/elbow articulation and wrist roll.
        for side,shoulder,elbow,hand in [('left',28,29,50),('right',31,32,51)]:
            a=chest_r.T@(world[elbow][1]-world[shoulder][1]);a=C@(a/max(1e-6,np.linalg.norm(a)))
            b=chest_r.T@(world[hand][1]-world[elbow][1]);b=C@(b/max(1e-6,np.linalg.norm(b)))
            out[side]=vec(np.array([-.23 if side=='left' else .23,1.456,0])+a*.30+b*.29)
            # A grip frame follows the actual source wrist. Blade +Y is the
            # source hand's transverse -X axis; +Z supplies the palm normal.
            wrist=C@chest_r.T@world[hand][0]
            blade_y=-wrist[:,0];blade_z=wrist[:,2]
            blade_x=np.cross(blade_y,blade_z);blade_x/=max(1e-6,np.linalg.norm(blade_x))
            blade_z=np.cross(blade_x,blade_y)
            out[side+'_rotation']=vec(euler(np.column_stack([blade_x,blade_y,blade_z])))
        hr=C@hip_r@C.T
        out['hip']=vec(euler(hr))
        out['chest']=vec(euler(C@hip_r.T@chest_r@C.T))
        shift=hip_p-origin
        out['hip_offset']=vec([np.clip(shift[0]*.008,-.06,.06),np.clip(shift[2]*.014,-.14,.06),np.clip(-shift[1]*.008,-.08,.08)])
        for side,index in [('left',8),('right',11)]:
            foot=C@(world[index][1]-hip_p)/70
            out[side+'_foot']=vec([max(-.44,min(.44,foot[0])),max(.035,min(.38,.946+foot[1])),max(-.48,min(.48,foot[2]))])
        frames.append(out)
    # Strip source locomotor heading, retaining its winding/pivot relative to
    # first pose. Cap extreme acrobatics to fit the existing grounded controller.
    for key in ['hip','chest','right_rotation','left_rotation']:
        vals=np.unwrap(np.array([f[key] for f in frames]),axis=0)
        if key=='hip':
            vals[:,1]-=vals[0,1]
            vals=np.clip(vals,[-.35,-1.8,-.22],[.4,1.8,.22])
        if key=='chest': vals=np.clip(vals,[-.5,-.8,-.3],[.55,.8,.3])
        for f,v in zip(frames,vals):f[key]=vec(v)
    speed=[]
    for i in range(1,len(frames)):
        a=np.array(frames[i-1]['right']);b=np.array(frames[i]['right'])
        speed.append(np.linalg.norm(b-a)/max(.001,frames[i]['t']-frames[i-1]['t']))
    # Search the drive, excluding idle entry/exit. Actual hit tuning remains
    # inspectable in content; animations and impact time share the same phase.
    candidates=[i for i in range(1,len(frames)) if .18<frames[i]['t']<.76]
    contact=frames[max(candidates,key=lambda i:speed[i-1])]['t']
    return sole_contacts({'duration':round(anim.duration,4),'contact':contact,'motion':frames})

def style(entry,source):
    f=entry['family'];s=source.lower()
    if any(x in s for x in ['rapier','estoc','mail breaker']):return 'rapier'
    return {'dagger':'knife','sword':'edge','greatsword':'greatblade','axe':'cleaver',
            'hammer':'maul','katana':'longcurve','spear':'lance','curved_sword':'crescent',
            'halberd':'glaive','scythe':'reaper','twin_blades':'paired','fist':'knuckles',
            'whip':'filament'}.get(f,'conduit')

def tailoring(name,g):
    n=name.lower();cloth=any(w in n for w in ['robe','dress','garb','cloth','hood','attire','skirt','pyromancer','cleric','sorcerer','fire keeper','black hand','assassin','worker','cornyx','karla','wrap'])
    heavy=any(w in n for w in ['cathedral','catarina','exile','smough','havel','gundyr','winged','morne'])
    ornate=any(w in n for w in ['dancer','silver knight','brass','dragonslayer','pontiff','fire witch','outrider','sunless','lorian','ornstein'])
    long=any(w in n for w in ['robe','dress','garb','coat','cornyx','karla','fire keeper','pontiff','black hand','legion','fallen','cleric','deacon','prayer','evangelist','jailer'])
    cape=any(w in n for w in ['alva','fallen','sellsword','wolf knight','knight armor','sunless','black hand','prayer','dragonscale','lothric','drakeblood'])
    bare=any(w in n for w in ['desert pyromancer','loincloth','master','rags','dragon form'])
    t={'cut':'cloth' if cloth else 'plate','waist':.165 if not heavy else .23,
       'chest':.245 if not heavy else .30,'depth':.152 if not heavy else .20,
       'shoulder':.095 if cloth else (.15 if heavy else .12),
       'layers':4 if heavy else (3 if ornate else 2),'ornate':ornate,'bare':bare,
       'hem':.78 if long else (.31 if heavy else .22),'cape':.66 if cape else 0,
       'mantle':any(w in n for w in ['fire keeper','deacon','cleric','evangelist','prayer']),
       'asymmetric':any(w in n for w in ['alva','fallen','sellsword','wolf knight','black hand']),
       'ragged':any(w in n for w in ['fallen','legion','ragged','worker','conjurator','pontiff','cornyx']),
       'ridge':any(w in n for w in ['dragonslayer','silver knight','lorian','wolf knight','black knight']),
       'crest':any(w in n for w in ['silver knight','black knight','dragonslayer','wolf knight','cathedral','winged']),
       'horns':any(w in n for w in ['gundyr','morne','smough','dragon','havel']),
       'visor':any(w in n for w in ['knight','cathedral','havel','morne','gundyr','lothric','faraam']),
       'hat':any(w in n for w in ['hat','karla','witch','sage']),
       'hood':any(w in n for w in ['hood','veil','fire keeper','prayer']),
       'crown':'crown' in n,'mask':any(w in n for w in ['mask','blindfold','crown of dusk'])}
    t['mimic']=name=='Symbol of Avarice'
    # Portrait bulk refines the curated cut, but cannot replace its construction.
    t['chest']=round(t['chest']*max(.94,min(1.08,float(g.get('bulk',.8)))),4)
    cuts={
      'Knight Armor':dict(hem=.24,shoulder=.105,layers=3),
      'Alva Armor':dict(hem=.48,cape=.72,asymmetric=True,shoulder=.105),
      'Fallen Knight Armor':dict(hem=.63,cape=.63,ragged=True,shoulder=.105,scarf=True),
      "Dancer's Armor":dict(waist=.135,chest=.226,depth=.137,shoulder=.08,hem=.35,ridge=True,ornate=True),
      'Fire Keeper Robe':dict(waist=.155,chest=.211,depth=.14,shoulder=.077,hem=.88,mantle=True),
      'Cathedral Knight Armor':dict(chest=.29,waist=.22,shoulder=.155,hem=.24,tabard=.68),
      "Gundyr's Armor":dict(chest=.278,waist=.21,shoulder=.16,layers=5,hem=.34),
      'Exile Armor':dict(chest=.335,waist=.29,depth=.23,shoulder=.14,hem=.32,layers=4),
      'Pontiff Knight Armor':dict(chest=.224,waist=.148,depth=.14,hem=.79,shoulder=.115,ragged=True,ornate=True),
      'Dragonslayer Armor':dict(chest=.25,waist=.155,depth=.16,hem=.40,ridge=True,shoulder=.145,ornate=True),
      'Black Hand Armor':dict(chest=.225,waist=.17,hem=.75,shoulder=.083,cape=.52,scarf=True),
      'Assassin Armor':dict(chest=.22,waist=.17,hem=.40,shoulder=.073,scarf=True),
      'Silver Knight Armor':dict(chest=.255,waist=.16,hem=.32,shoulder=.13,ridge=True,ornate=True),
      'Wolf Knight Armor':dict(chest=.239,waist=.15,hem=.61,shoulder=.11,ragged=True,ridge=True,cape=.75),
      'Brass Armor':dict(chest=.238,waist=.15,hem=.70,shoulder=.098,ornate=True,tabard=.70),
      'Archdeacon Holy Garb':dict(chest=.26,waist=.215,hem=.86,shoulder=.12,mantle=True,tabard=.84),
      'Desert Pyromancer Garb':dict(chest=.23,waist=.15,shoulder=.045,hem=.08,bare=True),
      'Catarina Armor':dict(chest=.33,waist=.29,depth=.245,shoulder=.15,hem=.25,layers=5),
      "Smough's Armor":dict(chest=.36,waist=.29,depth=.245,shoulder=.16,hem=.25,layers=5),
      "Havel's Armor":dict(chest=.30,waist=.25,depth=.21,shoulder=.17,hem=.24,layers=5),
      'Undead Legion Armor':dict(chest=.215,waist=.16,hem=.72,shoulder=.09,ragged=True,cape=.68),
      "Karla's Coat":dict(chest=.218,waist=.16,hem=.85,shoulder=.085,ragged=True,scarf=True),
      'Fire Witch Armor':dict(chest=.229,waist=.14,hem=.82,shoulder=.12,ornate=True,tabard=.80),
      'Eastern Armor':dict(chest=.25,waist=.20,hem=.40,shoulder=.13,layers=5,tabard=.44),
      'Dark Armor':dict(chest=.24,waist=.15,hem=.26,shoulder=.115,ridge=True,layers=4),
    }
    t.update(cuts.get(name,{}))
    return t

def portrait_tailoring(stream,t):
    """Measure reference proportions, keeping the Scribe's fitted 3D topology.

    Central garment sections deliberately exclude the outstretched sleeve tips.
    No pixels, projected texture or image plate are used in the runtime mesh.
    """
    im=np.asarray(Image.open(stream).convert('RGBA'))
    mask=(im[:,:,3]>180)&(im[:,:,:3].max(axis=2)>22)
    yy,xx=np.nonzero(mask)
    if len(xx)<100:return
    top,bottom=np.quantile(yy,[.01,.99]);left,right=np.quantile(xx,[.01,.99])
    center=(left+right)/2
    widths=[]
    for at in [.59,.49,.38,.29,.21]:
        band=mask[max(0,int(top+(bottom-top)*at)-3):int(top+(bottom-top)*at)+4]
        _,xs=np.nonzero(band)
        if len(xs)<8:widths.append(1);continue
        xs=xs[np.abs(xs-center)<(right-left)*.30]
        widths.append(float(np.quantile(xs,.92)-np.quantile(xs,.08)) if len(xs)>8 else 1)
    base=max(1,widths[0])
    t['contour']=[round(max(.80,min(1.25,w/base)),4) for w in widths]
    # Fabric hue comes from the portrait's midtones, dimmed into our neon world.
    pixels=im[:,:,:3][mask];value=pixels.max(axis=1);pixels=pixels[(value>35)&(value<180)]
    if len(pixels):
        rgb=np.median(pixels,axis=0);rgb=rgb/max(1,rgb.max())*.075
        t['fabric']=''.join(f'{int(n*255):02x}' for n in rgb)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--decoder',type=pathlib.Path,required=True);ap.add_argument('--reuse-motion',action='store_true');ap.add_argument('--references',type=pathlib.Path,default=pathlib.Path.home()/'Downloads');args=ap.parse_args()
    sys.path.insert(0,str(args.decoder.resolve()));from anim_skyrim import load_skyrim_animation
    private=ROOT/'.godot/equipment-references';audit=json.loads((private/'crosswalk.json').read_text(encoding='utf8'))
    cross={r['item_id']:r for r in audit['crosswalk']}
    bank_dir=DATA/'motions';bank_dir.mkdir(exist_ok=True)
    bank={};manifest={};provenance=[];skipped=[]
    if args.reuse_motion:
        bank={cut:json.loads((bank_dir/(cut+'.json')).read_text()) for cut in GROUPS}
        old=json.loads((private/'retarget_audit.json').read_text());provenance=old['clips'];skipped=old['skipped']
        manifest={cut:{'clips':len(clips),'frames':sum(len(c['motion']) for c in clips.values())} for cut,clips in bank.items()}
        for cut,clips in bank.items():
            for clip in clips.values():sole_contacts(clip)
            (bank_dir/(cut+'.json')).write_text(json.dumps(clips,separators=(',',':')),encoding='utf8')
    with zipfile.ZipFile(args.references/'DAR - Dark Souls Animated Armoury for ABR-103155-1-0-0-1702946612.zip') as z:
        for cut,groups in GROUPS.items():
            if args.reuse_motion:continue
            clips={};seen=set()
            for path in z.namelist():
                name=pathlib.PurePosixPath(path);group=name.parent.name
                if group not in groups or name.suffix.lower()!='.hkx' or 'backup' in path.lower():continue
                if not any(w in name.stem.lower() for w in ['attack','aabl','magic','bash']):continue
                raw=z.read(path);digest=hashlib.sha256(raw).hexdigest()
                if digest in seen:continue
                seen.add(digest);file=private/'motion_input.hkx';file.write_bytes(raw)
                try:clip=retarget(load_skyrim_animation(str(file)))
                except Exception as ex:skipped.append({'path':path,'reason':str(ex)});continue
                key='c'+digest[:12];clip['role']='power' if 'power' in name.stem.lower() or name.stem.lower().startswith('aabl') else 'basic'
                clips[key]=clip;provenance.append({'clip':key,'path':path,'sha256':digest})
            if not clips:
                # Some archive categories supply only idle replacements. A
                # conduit/whip still gets a motion vocabulary, explicitly
                # adapted from the closest available pole/curve gestures.
                fallback='crescent' if cut=='filament' else 'lance'
                clips=json.loads(json.dumps(bank[fallback]))
            bank[cut]=clips;manifest[cut]={'clips':len(clips),'frames':sum(len(c['motion']) for c in clips.values())}
            (bank_dir/(cut+'.json')).write_text(json.dumps(clips,separators=(',',':')),encoding='utf8')
            print(cut,manifest[cut],flush=True)
    catalog=json.loads((DATA/'catalog.json').read_text(encoding='utf8'))
    counters=collections.Counter()
    portraits={}
    for item in catalog['items']:
        source=cross[item['id']]['source'];g=item['geometry']
        item['acquisition']='Tower Exchange'
        corrected={"Cornyx's Wrap":"hands","Pyromancer Wrap":"hands","Grave Warden Wrap":"hands","Drang Shoes":"legs","Scholar's Shed Skin":"head","Symbol of Avarice":"head"}
        if source in corrected:
            item['legacy_slot']='body'
            item['family']=item['slot']=g['family']=corrected[source]
            item['name']=re.sub(r' Vestment$',{'head':' Visage','hands':' Bindings','legs':' Sabots'}[item['family']],item['name'])
        if item['category']=='weapons':
            cut=style(item,source);i=counters[cut];counters[cut]+=1;clips=bank[cut]
            basic=[k for k,v in clips.items() if v['role']=='basic'] or list(clips)
            power=[k for k,v in clips.items() if v['role']=='power'] or basic
            step=7
            while math.gcd(step,len(basic))!=1:step+=1
            art_step=3
            while math.gcd(art_step,len(power))!=1:art_step+=1
            # Each item owns a sequence recipe; related infusions keep the same
            # vocabulary but vary order, support hand, leverage and recovery.
            recipe={'cut':cut,'basic':[basic[(i*3+j*step)%len(basic)] for j in range(6)],
                    'arts':[power[(i*5+j*art_step)%len(power)] for j in range(4)],
                    'leverage':round(max(.78,min(1.12,1.03-(float(g['length'])-1.2)*.07)),5),
                    'tempo':round(.79+(i%19)*.0125,5),'stance':round(.17+(i%11)*.007,5),
                    'grip':round((i%13-6)*.004,5),'weight':round(.85+(i%17)*.019,5)}
            item['kind']='named';item['motion_set']=recipe
            item['attachment']={'primary_hand':'right','offhand':'left' if cut in ['paired','knuckles'] else 'support' if cut in ['greatblade','maul','longcurve','lance','glaive','reaper'] else 'free','stow':'left_hip' if cut=='longcurve' else 'back','model_axis':'+Y'}
            desc=item['description'].split(' Handling:')[0]
            desc=desc.split(' Named account:')[0]
            vocabulary={'knife':'close slipping cuts and a low returning point','edge':'alternating diagonal cuts and a planted closing stroke','rapier':'a narrow point, gathered rear hand and committed lunge','cleaver':'high elbows, cross-body chops and a weighty follow-through','greatblade':'two-handed loaded cuts, a wide base and a delayed recovery','maul':'an overhead load and a deep hip-driven impact','longcurve':'two-handed draw cuts and a gathering return','lance':'a sliding support grip, long point and braced rear foot','crescent':'flowing lateral cuts and an open-hip return','glaive':'a separated grip and sweeping whole-body turns','reaper':'low gathering sweeps followed by a high returning hook','paired':'alternating hands and crossing strikes over shifting support','knuckles':'short alternating strikes and close hip rotation','filament':'wide winding loops and a trailing recovery','conduit':'measured staff strikes and an elevated closing gesture'}
            # A named account describes a particular object, including the
            # variant's annotation, without inventing canonical faction history.
            weave=item['name'].split(' / ')[-1] if ' / ' in item['name'] else ''
            accounts=['a courier who practiced each turn in an empty doorway','a craftsperson who recorded repairs as part of the design','two neighbors who exchanged the weapon after every lesson','a quiet bearer who measured progress by the care of the return','an owner who kept the old grip after replacing every other part','a learner who left room in the margin for a different answer']
            account=accounts[i%len(accounts)]
            note=(' The '+weave+' annotation changes the sequence of the lesson, leaving the original maker\'s mark visible.') if weave else ' Its name was written inside the grip, where only the next bearer would find it.'
            item['description']=item['name']+' belonged to '+account+'.'+note+' Handling: '+vocabulary[cut]+'.'
        elif item['family'] in ['head','body','hands','legs']:
            g['tailoring']=tailoring(source,g)
            portrait=cross[item['id']].get('portrait')
            if portrait:
                archive=portrait['archive']
                if archive not in portraits:portraits[archive]=zipfile.ZipFile(args.references/archive)
                with portraits[archive].open(portrait['path']) as stream:portrait_tailoring(stream,g['tailoring'])
    for archive in portraits.values():archive.close()
    (DATA/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,separators=(',',':')),encoding='utf8')
    summary=json.loads((DATA/'summary.json').read_text());summary['families']=dict(collections.Counter(i['family'] for i in catalog['items']));summary['named_weapons']=sum(counters.values())+3
    (DATA/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf8')
    # Upgrade the three early named demonstrations too, retaining their authored
    # damage/timing identities while replacing the five-key analytic arm curves.
    named=json.loads((DATA/'named_weapons.json').read_text())
    for item,cut in zip(named['items'],['longcurve','lance','paired']):
        clips=list(bank[cut].values());cursor=0
        for action,sequence in item['moves'].items():
            for move in sequence:
                clip=clips[cursor%len(clips)];cursor+=1
                move['motion']=json.loads(json.dumps(clip['motion']))
                move['motion_contact']=clip['contact']
                move['grip_mode']='support' if cut!='paired' else 'left'
                move['retargeted']=True
                if action.endswith('_air'):
                    for frame in move['motion']:
                        frame['hip_offset']=[0,0,0];frame['hip'][0]*=.65;frame['chest'][0]*=.8
    (DATA/'named_weapons.json').write_text(json.dumps(named,separators=(',',':')),encoding='utf8')
    (bank_dir/'manifest.json').write_text(json.dumps({'version':1,'sets':manifest,'named_weapons':sum(counters.values())+3},indent=2),encoding='utf8')
    (private/'retarget_audit.json').write_text(json.dumps({'adapter':PARENTS,'clips':provenance,'skipped':skipped},indent=2),encoding='utf8')
    print('retargeted',len(provenance),'clips; skipped',len(skipped),'named',sum(counters.values())+3)

if __name__=='__main__':main()
