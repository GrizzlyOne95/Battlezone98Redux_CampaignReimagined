"""Restored cut voice lines that Redux's de/es/fr/it archives lack must ship with the mod:
valid PCM mono 11025 Hz 8-bit RIFF/WAVE (like the stock lines), admitted by the shipping lock,
backed by a subtitle, and actually referenced by the scripts (or the campaign ini)."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
WAVS = (['misn0232', 'misn0407', 'misn0426', 'misn0428']
        + ['misn06%02d' % n for n in range(15, 28)] + ['misn0639', 'misn0641', 'misn0652']
        + ['misn0910', 'misn0917', 'misn1224'])
lock = json.loads((root / 'Shipping/shipping.lock.json').read_text(encoding='utf-8'))
members = {e['source'].replace(chr(92), '/'): e['runtime'] for e in lock['files']}
sources = ''.join(p.read_text(encoding='utf-8', errors='replace')
                  for p in [*(root / 'Scripts').glob('*.lua'), root / 'Config/crcampgn.ini'])
for name in WAVS:
    wav = name + '.wav'
    data = (root / 'Assets/Audio' / wav).read_bytes()
    assert data[:4] == b'RIFF' and data[8:16] == b'WAVEfmt ', wav + ' is not a RIFF/WAVE file'
    assert int.from_bytes(data[20:22], 'little') == 1 and int.from_bytes(data[22:24], 'little') == 1
    assert int.from_bytes(data[24:28], 'little') == 11025 and int.from_bytes(data[34:36], 'little') == 8
    assert members.get('Assets/Audio/' + wav) == wav, 'Voice line must be admitted by the shipping manager: ' + wav
    assert (root / 'Text' / (name + '.txt')).is_file(), 'Voice line needs a subtitle: ' + name
    assert wav in sources, 'Voice line is not referenced by any script: ' + wav
print('shipped cut voice lines (%d) are valid, locked, subtitled and referenced' % len(WAVS))
