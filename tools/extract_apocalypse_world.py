"""World-state inputs for Apocalypse, from the local map (no game writes).

Keep native destructables outside the rendered crop. Fields__choose removes
one generated water family; Fields__setupRegions also moves gg_rct_Field via
an alias, so skeleton spawning uses the chosen pitch, not the original Rect.
"""
import collections
import hashlib
import json
import math
import re
from extract_assets import ROOT
from extract_scenery import placements, terrain


def main():
    script = (ROOT / 'research/war3map.j').read_text(encoding='utf-8')
    regions = {name: [float(v) for v in values.split(',')]
               for name, values in re.findall(r'set gg_rct_(\w+)=Rect\(([^)]+)\)', script)}
    catalog = json.loads((ROOT / 'assets/scenery/deaths/catalog.json').read_text(encoding='utf-8'))
    native = [p for p in placements() if p['id'] in catalog['types']]
    generated = []
    for zone, left, cols_extra, rows_extra, height in [('Frozen',1024,11,2,900), ('Waterfall',768,3,-1,1016)]:
        a,b,c,d = regions[zone]; sx = a-left
        cols = int((c-sx)/512+.6)+cols_extra
        rows = int((d-b)/512+.6)+rows_extra
        for x in range(cols):
            for y in range(rows):
                generated.append(dict(id='B000', variation=0, position=[sx+x*512,b+y*512,height],
                                      angle=math.pi/2, scale=[1,1,1], life=100,
                                      editor_id=-1, generated=zone))
    # Five random B001..B005 ice objects also belong to frozenWater[]. The
    # runtime chooses them once when constructing the world, before play.
    ice = []
    pattern = r"CreateDestructableZ\('B001'\+GetRandomInt\(0,4\),(.*?)\+GetRandomReal\(-400\.,400\.\),(.*?)\+GetRandomReal\(-400\.,400\.\),900\."
    for x,y in re.findall(pattern, script): ice.append([float(x),float(y)])
    assert len(ice)==5
    fields = json.loads((ROOT/'research/fields.json').read_text(encoding='utf-8'))['fields']
    land = terrain()
    result = dict(source_script_sha256=hashlib.sha256((ROOT/'research/war3map.j').read_bytes()).hexdigest(),
                  initial_playable_bounds=catalog['initial_playable_bounds'],
                  placed=native, generated_water=generated, generated_ice_centers=ice,
                  fields=[dict(id=f['id'], center=f['center'], zone=regions[f['id']],
                               pitch=f['regions']['Field']) for f in fields],
                  terrain=dict(size=land['size'], origin=land['origin'],
                               heights=[c['height'] for c in land['corners']]),
                  notes=['Absolute Warcraft XY/Z, not Godot coordinates.',
                         'Water family removal follows Fields__choose, including Sunny retaining waterfall water outside its zone.',
                         'gg_rct_Field is moved/resized indirectly through s__Fields__Rectangle_r; use chosen field pitch.',
                         'BizTree and franchise replacements are runtime mutations; the adapter must supply them.'])
    target=ROOT/'assets/scenery/apocalypse-world.json'
    target.write_text(json.dumps(result,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
    report=dict(placed=len(native),generated_water=dict(collections.Counter(p['generated'] for p in generated)),
                ice_templates=len(ice),terrain_size=land['size'],bytes=target.stat().st_size,
                sha256=hashlib.sha256(target.read_bytes()).hexdigest())
    (ROOT/'research/apocalypse-world-export.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report))


if __name__=='__main__': main()
