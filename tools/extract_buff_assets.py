"""Read the map's native buff attachment art, which is absent from JASS calls."""
import json, struct
from extract_assets import ROOT, MAP, read, extract, manifest, convert_textures


def read_buffs():
    data=read(MAP,'war3map.w3h'); offset=4; rows=[]
    for table in range(2):
        count=struct.unpack_from('<I',data,offset)[0]; offset+=4
        for _ in range(count):
            base,new,count=struct.unpack_from('<4s4si',data,offset); offset+=12; fields={}
            for _ in range(count):
                key,kind=struct.unpack_from('<4si',data,offset); offset+=8
                if kind==3:
                    end=data.index(0,offset); value=data[offset:end].decode('utf8'); offset=end+1
                else:
                    value=struct.unpack_from('<i' if kind==0 else '<f',data,offset)[0]; offset+=4
                fields[key.decode()]=value; offset+=4
            rows.append(dict(id=(new if table else base).decode(),base=base.decode(),fields=fields))
    assert offset==len(data)
    return rows


if __name__=='__main__':
    manifest.extend(json.loads((ROOT/'research/assets-manifest.json').read_text(encoding='utf8')))
    rows=read_buffs()
    (ROOT/'research/map-buffs.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf8')
    by_id={r['id']:r for r in rows}
    entries=json.loads((ROOT/'research/spell-assets.json').read_text(encoding='utf8'))
    # B003 uses the same sprite as B000 at the wisp's chest.
    sources={'B000':['fx_sprint'],'B001':['fx_super_sprint'],'B004':['fx_stealth_sprint'],
             'B005':['fx_slow'],'B00E':['fx_divine'],'B00F':['fx_ogre_left','fx_ogre_right'],
             'B00G':['fx_stun']}
    for buff,ids in sources.items():
        members=by_id[buff]['fields']['ftat'].split(',')
        assert len(ids)==len(members)
        for name,member in zip(ids,members):
            source=extract(member)
            if source is None:raise RuntimeError(member)
            entries=[e for e in entries if e['id']!=name]
            entries.append(dict(id=name,name=name,model_file=str(source.relative_to(ROOT)),model_member=member,
                                scale=1,animation='',prop=True,effect=True,buff=buff))
    # These are permanent ability attachments, not buff art.
    abilities=json.loads((ROOT/'research/abilities.json').read_text(encoding='utf8'))
    for ability,name in [('A01J','fx_silence'),('A00V','fx_shadow_trail')]:
        member=next(a for a in abilities if a['id']==ability)['fields']['atat_0']
        source=extract(member)
        if source is None:raise RuntimeError(member)
        entries=[e for e in entries if e['id']!=name]
        entries.append(dict(id=name,name=name.upper(),model_file=str(source.relative_to(ROOT)),model_member=member,
                            scale=1,animation='',prop=True,effect=True,ability=ability))
    (ROOT/'research/spell-assets.json').write_text(json.dumps(entries,ensure_ascii=False,indent=2),encoding='utf8')
    (ROOT/'research/assets-manifest.json').write_text(json.dumps(list({x['member'].lower():x for x in manifest}.values()),ensure_ascii=False,indent=2),encoding='utf8')
    print('Extracted',sum(map(len,sources.values()))+2,'native buff models')
