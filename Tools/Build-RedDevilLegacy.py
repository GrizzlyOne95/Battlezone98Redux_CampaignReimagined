"""Compile the selected legacy-guided diffuse, without changing model or optics."""
from pathlib import Path
import hashlib,json,sys
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parent))
from bcdds import save_bc
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'References/RedDevilLegacy'

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def build():
    recipe=json.loads((REF/'recipe.json').read_text());master=REF/recipe['master']
    # Preserve CR's existing cockpit-glass fix and every original UV exactly.
    assert (ROOT/recipe['mesh']).read_bytes()==(REF/'original/bvrdev.mesh').read_bytes()
    baseline=json.loads((REF/'original/bvrdev.material.json').read_text())['text']
    assert (ROOT/recipe['material']).read_text()==baseline,'refuse unrelated material changes'
    with Image.open(master) as im:
        authored_size=list(im.size);assert im.width==im.height
        assert max(recipe['size'][i]/im.size[i] for i in (0,1))<1.15,'do not invent resolution'
        diffuse=im.convert('RGB').resize(tuple(recipe['size']),Image.Resampling.LANCZOS)
    target=ROOT/recipe['output'];save_bc(diffuse,target,recipe['format'])
    receipt=dict(schema=1,master=recipe['master'],masterSha256=sha(master),authoredSize=authored_size,
        output=recipe['output'],size=recipe['size'],format=recipe['format'],sha256=sha(target),bytes=target.stat().st_size,
        meshSha256=sha(ROOT/recipe['mesh']),unchanged=['mesh','UVs','skeleton','native model','ODFs','material','normal/specular/emissive bindings'])
    (REF/'build.json').write_text(json.dumps(receipt,indent=2)+'\n',newline='\n')
    print('Red Devil: compiled selected diffuse only; mesh, UVs, gameplay and E/N/S bindings unchanged.')
if __name__=='__main__':build()
