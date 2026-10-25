"""Read the map's placed ground blockers, independently of its visual meshes.

This map uses live YTpb instances with an unscaled, solid 2x2 pathing texture.
Keep their original 32-unit cells; never infer a collider from a model AABB or
the smaller scripted Field/Goal_Area regions. Other scenery remains governed
by the exported WPM. This is deliberately not a general destructible importer.
"""
import hashlib
import json
from PIL import Image
from extract_assets import ROOT, extract, manifest
from extract_scenery import placements


def merge_cells(cells):
    """Merge equal horizontal runs vertically without filling any empty cell."""
    rows = {}
    for x, y in cells:
        rows.setdefault(y, []).append(x)
    rectangles, active = [], {}
    for y in sorted(rows):
        xs = sorted(rows[y]); runs = []; start = end = xs[0]
        for x in xs[1:]:
            if x == end + 1:
                end = x
            else:
                runs.append((start, end + 1)); start = end = x
        runs.append((start, end + 1))
        current = {}
        for run in runs:
            previous = active.get(run)
            if previous is not None and rectangles[previous][3] == y:
                rectangles[previous][3] = y + 1
                current[run] = previous
            else:
                current[run] = len(rectangles)
                rectangles.append([run[0], y, run[1], y + 1])
        active = current
    # Verify compression preserves exactly the source occupancy, including gaps.
    expanded = {(x, y) for x0, y0, x1, y1 in rectangles
                for y in range(y0, y1) for x in range(x0, x1)}
    assert expanded == cells
    return [[v * 32 for v in rect] for rect in rectangles]


def main():
    source = json.loads((ROOT/'research/scenery-source.json').read_text(encoding='utf8'))
    model = next(m for m in source['models'] if m['id'] == 'YTpb_0')
    member = model['source_row']['pathTex']
    manifest.extend(json.loads((ROOT/'research/assets-manifest.json').read_text(encoding='utf8')))
    texture = extract(member)
    with Image.open(texture) as image:
        assert image.size == (2, 2)
        assert all(pixel == (255, 0, 255) for pixel in image.convert('RGB').get_flattened_data())
    placed = [p for p in placements() if p['id'] == 'YTpb']
    fields = json.loads((ROOT/'research/fields.json').read_text(encoding='utf8'))['fields']
    result = []
    for field in fields:
        cx, cy = field['center']; bounds = field['terrain_sample_bounds']
        instances = []; cells = set()
        for p in placed:
            x, y, _ = p['position']; x -= cx; y -= cy
            if not (bounds[0] <= x < bounds[2] and bounds[1] <= y < bounds[3]):
                continue
            assert p['life'] > 0 and p['flags'] & 2
            assert p['scale'] == [1, 1, 1]
            assert x % 32 == 0 and y % 32 == 0
            # Every pixel is identical, so the authored 270-degree rotation
            # does not alter this footprint. Each pixel covers 32 world units.
            rect = [int(x - 32), int(y - 32), int(x + 32), int(y + 32)]
            cells.update((gx, gy) for gy in range(rect[1]//32, rect[3]//32)
                         for gx in range(rect[0]//32, rect[2]//32))
            instances.append({'editor_id': p['editor_id'], 'rect': rect})
        assert len(instances) == (248 if field['block_width'] == 32 else 280)
        merged = merge_cells(cells)
        result.append({'id': field['id'], 'instances': instances,
                       'cell_count': len(cells), 'rectangles': merged})
        print(field['id'], len(instances), 'placed blockers,', len(merged), 'merged rectangles')
    result = {'source': 'war3map.doo YTpb + original PathTextures/2x2Default.tga',
              'doo_sha256': hashlib.sha256((ROOT/'research/war3map.doo').read_bytes()).hexdigest(),
              'texture_sha256': hashlib.sha256(texture.read_bytes()).hexdigest(),
              'fields': result,
              'scope': 'Authored ground-blocker footprints. Ball/Object boundary events remain separate. Native unit-radius rasterization is not reconstructed here.'}
    (ROOT/'research/authored-pathing.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf8')
    (ROOT/'research/assets-manifest.json').write_text(json.dumps(list({m['member'].lower(): m for m in manifest}.values()), ensure_ascii=False, indent=2), encoding='utf8')


if __name__ == '__main__':
    main()
