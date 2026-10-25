"""Extract the original Apocalypse art; this does not enable the event in-game."""
import json
import subprocess
from extract_assets import ROOT, extract, convert_textures, manifest

MODELS = {
    'apoc_black_hole': r'war3mapImported\BlackHole2.mdx',
    'apoc_nuclear': r'war3mapImported\NuclearExplosion.mdx',
    'apoc_absorb': r'Abilities\Spells\Undead\OrbOfDeath\OrbOfDeathMissile.mdx',
    'apoc_fire_large': r'Doodads\Cinematic\TownBurningFireEmitter\TownBurningFireEmitter.mdx',
    'apoc_fire_small': r'Doodads\Cinematic\FireRockSmall\FireRockSmall.mdx',
    'apoc_animate_dead': r'Abilities\Spells\Undead\AnimateDead\AnimateDeadTarget.mdx',
    **{f'apoc_rubble_{i}': rf'Doodads\Outland\Rocks\RubbleRock\RubbleRock{i}.mdx' for i in range(4)},
    'apoc_skeleton': r'units\undead\Skeleton\Skeleton.mdx',
    'apoc_skeleton_archer': r'units\creeps\SkeletonArcher\SkeletonArcher.mdx',
}

def main():
    props_path = ROOT/'research/props.json'
    props = [p for p in json.loads(props_path.read_text(encoding='utf-8')) if p['id'] not in MODELS]
    for key, member in MODELS.items():
        source = extract(member)
        assert source, member
        props.append(dict(id=key, name=key, model_file=str(source.relative_to(ROOT)),
                          model_member=member, scale=1, animation='', prop=True,
                          apocalypse=True, material_layer_passes=True, source_bounds=True,
                          particle_capacity=1024 if key == 'apoc_black_hole' else 512))
    props_path.write_text(json.dumps(props, ensure_ascii=False, indent=2), encoding='utf-8')
    textures = []
    for key in MODELS:
        subprocess.run(['node', str(ROOT/'tools/convert_models.cjs'), '--only', key], cwd=ROOT, check=True)
        model = json.loads((ROOT/f'assets/models/{key}.json').read_text(encoding='utf-8'))
        for texture in model['textures']:
            member = texture['Image']
            if not member:
                continue
            source = extract(member)
            assert source, member
            textures.append(source)
    convert_textures(textures)
    (ROOT/'research/apocalypse-assets-manifest.json').write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    print('Extracted', len(MODELS), 'Apocalypse models and', len(set(textures)), 'textures')

if __name__ == '__main__':
    main()
