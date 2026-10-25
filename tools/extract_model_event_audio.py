"""Extract original EVTS SND audio from the user's archives, preserving provenance."""
import json,wave,hashlib
from extract_assets import ROOT,extract,manifest

definitions=json.loads((ROOT/'research/model-event-definitions.json').read_text(encoding='utf-8'))['definitions']
folder=ROOT/'assets/audio/model-events';folder.mkdir(exist_ok=True)
catalog={};missing=[];muted=[];runtime={}
for event in definitions:
    if event['type']!='SND':continue
    row=event['sound_definition'];files=[];absent=[];silent=[]
    for filename in row['FileNames'].split(','):
        source=extract(row['DirectoryBase']+filename.strip())
        if source is None:
            absent.append(row['DirectoryBase']+filename);missing.extend(absent[-1:]);continue
        destination=folder/source.name
        # Empty map overrides intentionally suppress stock death/silence audio.
        # Never fall back to the base archive or feed a zero-byte WAV to Godot.
        if source.stat().st_size==0:
            silent.append(row['DirectoryBase']+filename);muted.extend(silent[-1:])
            if destination.exists() and destination.stat().st_size==0:
                assert destination.resolve().parent==folder.resolve()
                destination.unlink()
            continue
        # Some legacy WAVs have malformed trailing editor chunks. Keep every
        # PCM sample, channel, rate and bit depth, and rebuild only the RIFF
        # container so Godot's importer does not seek beyond the file.
        with wave.open(str(source),'rb') as reader:
            params=reader.getparams();pcm=reader.readframes(params.nframes)
            assert len(pcm)==params.nframes*params.nchannels*params.sampwidth
        with wave.open(str(destination),'wb') as writer:
            writer.setparams(params);writer.writeframes(pcm)
        with wave.open(str(destination),'rb') as reader:
            assert reader.getparams()==params and reader.readframes(params.nframes)==pcm
        runtime[destination.name]={'source':str(source.relative_to(ROOT)),'frames':params.nframes,'channels':params.nchannels,'sample_width':params.sampwidth,'sample_rate':params.framerate,'pcm_sha256':hashlib.sha256(pcm).hexdigest(),'runtime_sha256':hashlib.sha256(destination.read_bytes()).hexdigest()}
        files.append('res://'+destination.relative_to(ROOT).as_posix())
    catalog[event['code']]={'files':files,'source':row,'missing':absent,'muted_map_overrides':silent}
(ROOT/'research/model-event-audio-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
(ROOT/'research/model-event-audio-gaps.json').write_text(json.dumps({'missing':missing,'muted_map_overrides':muted},indent=2),encoding='utf-8')
(folder/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2),encoding='utf-8')
(ROOT/'research/model-event-audio-pcm-verification.json').write_text(json.dumps(runtime,indent=2),encoding='utf-8')
print('Original audio codes:',len(catalog),'source records:',len(manifest),'unique files:',len(list(folder.glob('*.wav'))))
