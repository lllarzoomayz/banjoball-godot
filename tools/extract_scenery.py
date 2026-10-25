"""Extract placed scenery and terrain from the user's local 1.27 map, read-only.

Binary layout references: flowtsohg/mdx-m3-viewer parsers/w3x/{doo,w3e}.
Outputs are visual data only: collision continues to use fields.json and WPM.
"""
import collections, hashlib, json, math, re, struct, sys
from extract_assets import ROOT, extract, manifest, safe_name


def slk(path):
    cells = collections.defaultdict(dict)
    x = y = 1
    for line in path.read_text(encoding='utf8', errors='replace').splitlines():
        if not line.startswith('C;'):
            continue
        for token in re.findall(r'(?:[^;"\r\n]|"(?:[^"]|"")*")+', line[2:]):
            if token.startswith('X'): x = int(token[1:])
            elif token.startswith('Y'): y = int(token[1:])
            elif token.startswith('K'):
                value = token[1:]
                if value.startswith('"'): value = value[1:-1].replace('""', '"')
                else:
                    try: value = float(value) if '.' in value else int(value)
                    except ValueError: pass
                cells[y][x] = value
    headers = cells.pop(1)
    return {v[1]: {headers[k]: value for k, value in v.items() if k in headers} for v in cells.values() if 1 in v}


def modified_table(base_name, meta_name, extension):
    base = slk(extract(base_name))
    meta = slk(extract(meta_name))
    b = (ROOT / 'research' / ('war3map.' + extension)).read_bytes()
    p = 4
    for table in range(2):
        count, = struct.unpack_from('<I', b, p); p += 4
        for _ in range(count):
            old, new, n = struct.unpack_from('<4s4sI', b, p); p += 12
            old, new = old.decode(), new.decode()
            row = base[old].copy()
            for _ in range(n):
                key, kind = struct.unpack_from('<4sI', b, p); p += 8
                variation = 0
                if extension == 'w3d':
                    variation, pointer = struct.unpack_from('<II', b, p); p += 8
                if kind == 3:
                    end = b.index(0, p)
                    value = b[p:end].decode('utf8', errors='replace'); p = end + 1
                else:
                    value, = struct.unpack_from('<i' if kind == 0 else '<f', b, p); p += 4
                p += 4
                field = meta[key.decode()]['field']
                if extension == 'w3d' and meta[key.decode()].get('repeat', 0):
                    field += f'{variation:02d}'
                row[field] = value
            base[new if table else old] = row
    assert p == len(b), (extension, p, len(b))
    return base


def placements():
    b = (ROOT / 'research/war3map.doo').read_bytes()
    magic, version, subversion, count = struct.unpack_from('<4sIII', b)
    assert (magic, version, subversion) == (b'W3do', 8, 11)
    p = 16; result = []
    for _ in range(count):
        raw, variation, x, y, z, angle, sx, sy, sz, flags, life = struct.unpack_from('<4si7fBB', b, p); p += 38
        table, sets = struct.unpack_from('<II', b, p); p += 8
        for _ in range(sets):
            n, = struct.unpack_from('<I', b, p); p += 4 + n * 8
        editor_id, = struct.unpack_from('<i', b, p); p += 4
        result.append(dict(id=raw.decode(), variation=variation, position=[x, y, z], angle=angle,
                           scale=[sx, sy, sz], flags=flags, life=life, editor_id=editor_id))
    terrain_version, terrain_count = struct.unpack_from('<II', b, p); p += 8
    assert terrain_count == 0 and p == len(b), 'Unexpected terrain doodads'
    return result


def terrain():
    b = (ROOT / 'research/war3map.w3e').read_bytes()
    assert b[:4] == b'W3E!'
    p = 13; lists = []
    for _ in range(2):
        count, = struct.unpack_from('<I', b, p); p += 4
        lists.append([b[p+i*4:p+i*4+4].decode() for i in range(count)]); p += 4*count
    nx, ny, ox, oy = struct.unpack_from('<IIff', b, p); p += 16
    assert len(b) - p == 7*nx*ny
    corners = []
    for i in range(nx*ny):
        ground, water, flags, variation, cliff = struct.unpack_from('<hhBBB', b, p+7*i)
        corners.append(dict(height=(ground-8192)/4+((cliff&15)-2)*128,
                            ground=flags&15, variation=variation&31, layer=cliff&15,
                            water=(water&0x3fff)/4-2048, flags=flags))
    return dict(size=[nx, ny], origin=[ox, oy], tiles=lists[0], cliffs=lists[1], corners=corners)


def main():
    manifest.extend(json.loads((ROOT/'research/assets-manifest.json').read_text(encoding='utf8')))
    if '--textures' in sys.argv:
        conversion = json.loads((ROOT/'research/scenery-conversion.json').read_text(encoding='utf8'))
        for name in conversion['textures']:
            assert extract(name), name
        (ROOT/'research/assets-manifest.json').write_text(json.dumps(list({x['member'].lower():x for x in manifest}.values()),ensure_ascii=False,indent=2),encoding='utf8')
        return
    table = modified_table('Doodads\\Doodads.slk', 'Doodads\\DoodadMetaData.slk', 'w3d')
    table.update(modified_table('Units\\DestructableData.slk', 'Units\\DestructableMetaData.slk', 'w3b'))
    land = terrain(); nx, ny = land['size']; ox, oy = land['origin']
    tiles = slk(extract('TerrainArt\\Terrain.slk'))
    tile_assets = []
    for tile_id in land['tiles']:
        row = tiles.get(tile_id)
        if not row: raise ValueError('Unknown terrain tile ' + tile_id)
        name = row['dir'] + '\\' + row['file'] + '.blp'
        source = extract(name)
        assert source, name
        tile_assets.append(dict(id=tile_id, member=name, source=str(source.relative_to(ROOT))))
    placed = placements(); models = {}; field_scenes = []; missing = []; skipped = []
    # Fields__init creates these WaterPlane destructibles at runtime rather than
    # storing them in DOO. Mirror both deterministic grids, before field cropping.
    script = (ROOT/'research/war3map.j').read_bytes().decode('gb18030',errors='replace')
    regions = {name:[float(v) for v in values.split(',')] for name,values in re.findall(r'set gg_rct_(\w+)=Rect\(([^)]+)\)',script)}
    for zone, left_extra, columns_extra, rows_extra, height in [('Frozen',1024,11,2,900),('Waterfall',768,3,-1,1016)]:
        a,b,c,d = regions[zone]; sx=a-left_extra; sy=b
        columns=int((c-sx)/512+.6)+columns_extra; rows=int((d-sy)/512+.6)+rows_extra
        for x in range(columns):
            for y in range(rows):
                placed.append(dict(id='B000',variation=0,position=[sx+512*x,sy+512*y,height],angle=math.pi/2,
                                   scale=[1,1,1],flags=2,life=100,editor_id=-1,generated=zone))
    fields = json.loads((ROOT/'research/fields.json').read_text(encoding='utf8'))['fields']
    for field in fields:
        cx, cy = field['center']; r = field['regions']['Field']
        # Keep a substantial authored backdrop beyond both touchlines and goals.
        x0 = max(0, math.floor((cx+r[0]-1536-ox)/128)); x1 = min(nx-1, math.ceil((cx+r[2]+1536-ox)/128))
        y0 = max(0, math.floor((cy+r[1]-1280-oy)/128)); y1 = min(ny-1, math.ceil((cy+r[3]+1792-oy)/128))
        base = land['corners'][round((cy-oy)/128)*nx+round((cx-ox)/128)]['height']
        bounds = [ox+128*x0-cx, oy+128*y0-cy, ox+128*x1-cx, oy+128*y1-cy]
        scene = dict(id=field['id'], name=field['name'], center=[cx, cy], base_height=base,
                     bounds=bounds, grid=[x1-x0+1, y1-y0+1], tile_assets=tile_assets,
                     corners=[land['corners'][y*nx+x] for y in range(y0, y1+1) for x in range(x0, x1+1)], placements=[])
        for d in placed:
            x, y, z = d['position']; x -= cx; y -= cy
            if not (bounds[0] <= x <= bounds[2] and bounds[1] <= y <= bounds[3]): continue
            if d.get('generated')=='Frozen' and field['id'] not in ['Frozen','Frozen_Coast']: continue
            if d.get('generated')=='Waterfall' and field['id']!='Waterfall': continue
            row = table[d['id']]; model = row.get('file', '')
            if not model or model == '_' or not (d['flags'] & 2):
                skipped.append(dict(field=field['id'], editor_id=d['editor_id'], id=d['id'], reason='hidden_or_no_model')); continue
            key = d['id'] + '_' + str(d['variation'])
            if key not in models:
                stem = re.sub(r'\.(mdx|mdl)$', '', model, flags=re.I)
                name = stem + (str(min(d['variation'], int(row.get('numVar',1))-1)) if int(row.get('numVar',1)) > 1 else '') + '.mdx'
                source = extract(name)
                if not source and name != stem+'.mdx':
                    name = stem+'.mdx'; source = extract(name)
                if not source:
                    missing.append(dict(key=key, member=name)); continue
                replacement = row.get('texFile', '')
                if replacement and replacement != '_':
                    if not re.search(r'\.(blp|tga)$', replacement, re.I): replacement += '.blp'
                    assert extract(replacement), replacement
                else: replacement = ''
                var = f'{d["variation"]+1:02d}'
                tint = [float(row.get('vert'+channel+var, row.get('color'+channel,255)))/255 for channel in 'RGB']
                models[key] = dict(id=key, member=name, source=str(source.relative_to(ROOT)),
                                   replacement=replacement, replacement_id=row.get('texID',0), tint=tint,
                                   pathing=row.get('pathTex',''), source_row=row)
            scene['placements'].append(dict(key=key, editor_id=d['editor_id'], position=[x,y,z-base],
                                            angle=d['angle'], scale=d['scale'], life=d['life']))
        field_scenes.append(scene)
        print(field['id'],len(scene['placements']),'placements',scene['grid'],'vertices')
    out = dict(fields=field_scenes, models=list(models.values()), missing=missing, skipped=skipped,
               sources={name:hashlib.sha256((ROOT/'research'/name).read_bytes()).hexdigest() for name in ['war3map.doo','war3map.w3e','war3map.w3d','war3map.w3b']},
               caveats=['Static pose scenery. No new collision from appearance.', 'Water grids include the original model but UV animation and steam particles are not implemented.', 'No randomized floating ice, weather, changing franchise banners or cliff models yet.'])
    (ROOT/'research/scenery-source.json').write_text(json.dumps(out,ensure_ascii=False),encoding='utf8')
    (ROOT/'research/assets-manifest.json').write_text(json.dumps(list({x['member'].lower():x for x in manifest}.values()),ensure_ascii=False,indent=2),encoding='utf8')
    print('Models',len(models),'missing',missing,'skipped',len(skipped))


if __name__ == '__main__': main()
