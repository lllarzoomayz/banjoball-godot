"""Inventory actual destructables separately from decorative doodads."""
import json, re, subprocess, wave, hashlib
from extract_assets import ROOT, manifest, extract, convert_textures
from extract_scenery import modified_table, placements, slk

def main():
    types = modified_table(r'Units\DestructableData.slk', r'Units\DestructableMetaData.slk', 'w3b')
    original = [p for p in placements() if p['id'] in types]
    source = json.loads((ROOT/'research/scenery-source.json').read_text(encoding='utf-8'))
    used = {p['id'] for p in original} | {'B000','B001','B002','B003','B004','B005'}
    entries = [m for m in source['models'] if m['id'].split('_')[0] in used and m['id'].split('_')[0] != 'YTpb']
    assert all(any(m['id'] == f'{kind}_{i}' for m in entries) for kind in ['LTlt','WTst'] for i in range(10))
    script = (ROOT/'research/war3map.j').read_text(encoding='utf-8')
    zones = {}
    for name in ['Sunny_Hills','Waterfall','Frozen','Frozen_Coast']:
        found = re.search(r'set gg_rct_'+name+r'=Rect\(([^)]+)\)', script)
        assert found, name
        zones[name] = [float(x) for x in found[1].split(',')]
    plan = {'models': entries, 'types': {k: types[k] for k in sorted(used)},
            'native_placements': original, 'field_zones': zones,
            'initial_playable_bounds': [-7552,-4480,15744,27008],
            'tree_unit_art': {'LTlt':'h01K','WTst':'h01L'},
            'note': 'A native destructable inventory, not all scenery. Generated water planes have no Death sequence; their native missing-sequence fallback is not calibrated.'}
    (ROOT/'research/destructable-death-source.json').write_text(json.dumps(plan,ensure_ascii=False),encoding='utf-8')
    subprocess.run(['node', str(ROOT/'tools/export_destructable_deaths.cjs')], cwd=ROOT, check=True)
    catalog=json.loads((ROOT/'assets/scenery/deaths/catalog.json').read_text(encoding='utf-8'))
    textures=[]
    for row in catalog['models'].values():
        for geo in row.get('meshes',[]):
            if geo['texture']:
                path=extract(geo['texture']);assert path;textures.append(path)
    convert_textures(textures)
    sounds=slk(extract(r'UI\SoundInfo\AnimSounds.slk'))
    sound_catalog={};pcm_report={};folder=ROOT/'assets/audio/scenery-events';folder.mkdir(exist_ok=True)
    for label in sorted({r.get('deathSnd','_') for r in plan['types'].values()}-{'_',''}):
        row=sounds[label];files=[];muted=[]
        for filename in row['FileNames'].split(','):
            member=row['DirectoryBase']+filename.strip();original_file=extract(member);assert original_file, member
            if original_file.stat().st_size==0:muted.append(member);continue
            with wave.open(str(original_file),'rb') as reader:
                params=reader.getparams();pcm=reader.readframes(params.nframes)
            destination=folder/original_file.name
            with wave.open(str(destination),'wb') as writer:writer.setparams(params);writer.writeframes(pcm)
            with wave.open(str(destination),'rb') as reader:assert reader.getparams()==params and reader.readframes(params.nframes)==pcm
            files.append('res://'+destination.relative_to(ROOT).as_posix())
            pcm_report[member]={'frames':params.nframes,'rate':params.framerate,'channels':params.nchannels,'sample_width':params.sampwidth,'pcm_sha256':hashlib.sha256(pcm).hexdigest()}
        sound_catalog[label]={'files':files,'source':row,'muted_map_overrides':muted}
    (folder/'catalog.json').write_text(json.dumps({'types':{k:v.get('deathSnd','_') for k,v in plan['types'].items()},'sounds':sound_catalog},ensure_ascii=False,indent=2),encoding='utf-8')
    (ROOT/'research/destructable-audio-pcm-verification.json').write_text(json.dumps(pcm_report,indent=2),encoding='utf-8')
    (ROOT/'research/destructable-death-assets-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print('Native destructables',len(original),'rendered death variants',sum(r['status']=='death' for r in catalog['models'].values()))

if __name__=='__main__':main()
