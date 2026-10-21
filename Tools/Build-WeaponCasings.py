"""Author explicit local casing choices while preserving all gameplay fields."""
from pathlib import Path
import argparse
import json
import re

ROOT = Path(__file__).resolve().parents[1]
BEGIN, END = '// CR WEAPON CASING BEGIN', '// CR WEAPON CASING END'


def strip_block(text):
    if BEGIN in text:
        a = text.index(BEGIN)
        b = text.index(END, a) + len(END)
        if text[b:b+1] == '\n':
            b += 1
        text = text[:a] + text[b:]
    return text


def authored_odf(source, choice):
    text = strip_block(source.replace('\r\n', '\n'))
    section = re.search(r'(?im)^[ \t]*\[WeaponClass\][^\n]*\n', text)
    assert section, 'missing WeaponClass section'
    at = section.end()
    flash_end = text.find('// CR WEAPON FLASH END', at)
    # Keep both generators idempotent: flash first, casing second.
    if flash_end >= 0:
        at = flash_end + len('// CR WEAPON FLASH END')
        if text[at:at+1] == '\n':
            at += 1
    kind = choice['casing_type']
    assert kind in ('none', 'small', 'medium', 'large')
    block = (f'{BEGIN}\n// {choice["casing_decision"]}\n'
             f'casingType = "{kind}"\n{END}\n')
    return text[:at] + block + text[at:]


def build(stock, check):
    config = json.loads((ROOT/'References/WeaponPresentation/profiles.json').read_text())
    for name, choice in config['weapons'].items():
        path = ROOT/'ODF'/(name+'.odf')
        source = path if path.exists() else stock/(name+'.odf')
        output = authored_odf(source.read_text(), choice)
        if check:
            assert path.read_text() == output, f'{name}: casing block differs; regenerate'
        else:
            path.write_bytes(output.encode())
    print(f'Weapon casings: {len(config["weapons"])} explicit choices checked')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stock', type=Path, default=ROOT/'ODF')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    build(args.stock, args.check)
