"""Read the standard field's regions and terrain pathing from the local map.

No inferred doodad collision is imported. The chosen playable area contains no
unwalkable WPM cells; the optional obstacle courses are explicitly new practice.
"""
import hashlib, json, pathlib, re, struct, collections
ROOT = pathlib.Path(__file__).resolve().parents[1]
j = (ROOT / 'research/war3map.j').read_bytes().decode('gb18030', errors='replace')
center = [-2048, 11520]
regions = {}
for name, values in re.findall(r'set gg_rct_(\w+)=Rect\(([^)]+)\)', j):
    coords = [float(x) for x in values.split(',')]
    regions[name] = [v - center[i % 2] for i, v in enumerate(coords)]
setup = j.split('function Boundary__setupBounds')[1].split('endfunction')[0]
boundaries = []
for index, name in re.findall(r'RegionAddRect\(Boundary__bounds\[(\d+)\],gg_rct_(\w+)\)', setup):
    angle = int(re.search(r'GetHandleId\(Boundary__bounds\['+index+r'\]\),(\d+)\)', setup)[1])
    boundaries.append(dict(name=name, rect=regions[name], normal_degrees=angle,
                           min_height=300 if int(index)>=16 else 0, max_height=32468))
w = (ROOT/'research/war3map.wpm').read_bytes()
_, _, nx, ny = struct.unpack_from('<4sIII', w)
e = (ROOT/'research/war3map.w3e').read_bytes()
offset = 13
for _ in range(2):
    n, = struct.unpack_from('<I', e, offset)
    offset += 4+4*n
_, _, ox, oy = struct.unpack_from('<IIff', e, offset)
playable = [regions[n] for n in ['Field', 'Goal_1_Area', 'Goal_2_Area']]
counts = collections.Counter()
blocked = []
for y in range(ny):
    for x in range(nx):
        px, py = ox+x*32+16-center[0], oy+y*32+16-center[1]
        if any(r[0]<=px<r[2] and r[1]<=py<r[3] for r in playable):
            flags = w[16+y*nx+x]
            counts[flags] += 1
            if flags & 2:
                blocked.append([px-16, py-16, px+16, py+16])
data = dict(source='弹跳足球_1.27兼容版 / standard field', center=center,
            script_sha256=hashlib.sha256((ROOT/'research/war3map.j').read_bytes()).hexdigest(),
            regions={n: regions[n] for n in ['Field','Goal_1','Goal_2','Goal_1_Area','Goal_2_Area','Goal_1_Front','Goal_2_Front','Goal_1_Front_Face','Goal_2_Front_Face']},
            boundaries=boundaries, terrain_blocked=blocked, pathing_flag_counts=dict(counts),
            caveat='Static initial regions. Native 32-cell region rasterization, relocated fields and runtime destructibles are not emulated.')
(ROOT/'research/arena.json').write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf8')
print(f'Extracted {len(boundaries)} ball boundaries, {sum(counts.values())} playable terrain cells, {len(blocked)} unwalkable cells.')
