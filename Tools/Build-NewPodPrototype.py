"""Purpose-built ammo canister and repair case, render prototypes only.

Shared static mesh serializer; no native collision, pickup behavior or shipped
assets are changed. Uses the v3 art to compare new silhouettes with stock ones.
"""
from pathlib import Path
import hashlib,io,json,math,sys
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'Tools'))
from bzstaticmodel import static_mesh_bytes
from bzmodellibs import ogremesh as om,ogremesh_serializer as oms
from bcdds import save_bc
OUT=ROOT/'References/TextureRevamp/pod-uv-v3'

class Model:
    def __init__(self,name,atlas):self.name=name;self.atlas=atlas;self.rows={'body':[],'trim':[]}
    def face(self,points,uv,group='body'):
        points=np.asarray(points,float);n=np.cross(points[1]-points[0],points[2]-points[0]);length=np.linalg.norm(n)
        assert length>1e-8,'degenerate authored face'
        n/=length
        for i in range(1,len(points)-1):
            for k in (0,i,i+1):self.rows[group].append([*points[k],*n,*uv[k]])
    def sample(self,u,v):return (.08+u*.012,.24+v*.004) if self.atlas=='cramns3' else (.08+u*.012,.818+v*.005)
    def top(self,x,z):
        if self.atlas=='crhpns3':return (.03+.65*(x+1.17)/2.34,.03+.65*(1.17-z)/2.34)
        return (.50+x*.025,.61-z*.025)
    def loft(self,profile,role='body',segments=16):
        rings=[[(math.sin(2*math.pi*(i/segments-.5))*r,y,math.cos(2*math.pi*(i/segments-.5))*r) for i in range(segments)] for y,r in profile]
        low,high=profile[0][0],profile[-1][0]
        def coords(i,y):
            t=(y-low)/(high-low)
            if role=='body' and self.atlas=='cramns3':return (.04+.92*i/segments,.238-t*.158)
            if role=='upper':return (.06+.88*i/segments,.53-t*.195)
            if role=='shell':return (.03+.94*i/segments,.837-t*.058)
            return self.sample(i/segments,t)
        group='trim' if role=='trim' else 'body'
        for j in range(len(rings)-1):
            for i in range(segments):
                k=(i+1)%segments
                self.face([rings[j][i],rings[j][k],rings[j+1][k],rings[j+1][i]],
                          [coords(i,profile[j][0]),coords(i+1,profile[j][0]),coords(i+1,profile[j+1][0]),coords(i,profile[j+1][0])],group)
        for j,reverse in ((0,True),(len(rings)-1,False)):
            ring=rings[j];center=(0,profile[j][0],0)
            for i in range(segments):
                pts=[center,ring[i],ring[(i+1)%segments]]
                uv=[self.top(q[0],q[2]) for q in pts] if role in ('shell','cap') else [self.sample(.5,.5),self.sample(.4,.4),self.sample(.6,.4)]
                if reverse:pts.reverse();uv.reverse()
                self.face(pts,uv,group)
    def box(self,center,half,role='trim'):
        x,y,z=center;a,b,c=half
        vertices=[(x+sx*a,y+sy*b,z+sz*c) for sx,sy,sz in ((-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1))]
        for ids in ((0,3,2,1),(4,5,6,7),(0,4,7,3),(1,2,6,5),(0,1,5,4),(3,7,6,2)):
            if role=='green':uv=[(.15,.809),(.17,.809),(.17,.816),(.15,.816)]
            else:uv=[self.sample(0,0),self.sample(1,0),self.sample(1,1),self.sample(0,1)]
            self.face([vertices[i] for i in ids],uv,'body' if role=='green' else 'trim')
    def save(self):
        texture=self.name if self.name=='crhpnew3' else self.atlas
        if texture==self.name:
            with Image.open(OUT/(self.name+'-master.png')) as image:save_bc(image.convert('RGB').resize((1024,1024),Image.Resampling.LANCZOS),OUT/(texture+'_d.dds'))
        parts=[];allrows=[]
        for group,rows in self.rows.items():
            if not rows:continue
            mesh=oms.MeshSerializer(io.BytesIO(static_mesh_bytes(self.name+('/trim' if group=='trim' else ''),rows,range(len(rows))))).read()
            parts.append(mesh.submesh_list[0]);allrows.extend(rows)
        mesh.submesh_list=parts
        for i,sub in enumerate(parts):sub.parent=mesh;sub.submesh_index=i
        xyz=np.asarray(allrows)[:,:3];low=xyz.min(0);high=xyz.max(0)
        mesh.aabb=om.AxisAlignedBoundingBox(*low,*high);mesh.bound_radius=float(np.linalg.norm(xyz,axis=1).max())
        stream=io.BytesIO();oms.MeshSerializer(stream).write(mesh);path=OUT/(self.name+'.mesh');path.write_bytes(stream.getvalue())
        text='\n'.join(['import * from "CR_BZBase.material"',f'material {self.name} : CR_BZBase','{',
            f'    set_texture_alias DiffuseMap {texture}_d.dds','    set_texture_alias NormalMap flat_N.dds',
            '    set_texture_alias SpecularMap crvcca_patch_s.dds','    set_texture_alias EmissiveMap black.dds',
            '    set $diffuse "1 1 1"','    set $ambient "1 1 1"','    set $specular ".15 .15 .15"','    set $shininess "32"','}',
            f'material {self.name}/trim : {self.name}','{','    set $diffuse "0.24 0.24 0.24"','    set $ambient "0.24 0.24 0.24"','}',''])
        (OUT/(self.name+'.material')).write_text(text,newline='\n')
        result={'atlas':texture,'triangles':len(allrows)//3,'batches':len(parts),'bounds':[low.tolist(),high.tolist()],
                'meshSha256':hashlib.sha256(path.read_bytes()).hexdigest(),'unskinned':True,'nativeCollisionAuthored':False}
        print(self.name,result['triangles'],'new triangles;',len(parts),'materials; bounds',result['bounds'])
        return result

def build():
    ammo=Model('cramnew3','cramns3')
    # Protective boot, a barrel with broad uninterrupted paint, shallow lid.
    ammo.loft([(.15,.67),(.20,.79),(.31,.79),(.36,.73)],'trim')
    ammo.loft([(.29,.69),(.36,.73),(1.35,.73),(1.48,.68)],'body')
    ammo.loft([(1.46,.69),(1.52,.76),(1.62,.76),(1.67,.69)],'trim')
    ammo.loft([(1.61,.63),(1.74,.59),(1.80,.44)],'upper')
    ammo.loft([(1.80,.43),(1.85,.40)],'cap')
    # A real grab handle makes this read as a supply container, not a missile.
    for x in (-.60,.60):ammo.box((x,1.80,0),(.055,.25,.095))
    ammo.box((0,2.04,0),(.65,.06,.095))
    for x,z in ((.73,0),(-.73,0),(0,.73),(0,-.73)):
        ammo.box((x,1.35,z),(.065 if x else .11,.14,.065 if z else .11))
    repair=Model('crhpnew3','crhpns3')
    # Low armored maintenance case with an ivory lid and four green cartridges.
    repair.loft([(.13,.88),(.18,1.04),(.31,1.04),(.36,.98)],'trim',segments=8)
    repair.loft([(.31,.94),(.40,1.03),(.72,1.03),(.85,.89)],'shell',segments=8)
    repair.loft([(.86,.48),(.91,.44),(1.12,.39),(1.17,.34)],'shell',segments=8)
    for x,z in ((.95,0),(-.95,0),(0,.95),(0,-.95)):
        repair.box((x,.59,z),(.08 if x else .22,.14,.08 if z else .22),'green')
    for x,z in ((.72,.72),(-.72,.72),(-.72,-.72),(.72,-.72)):
        repair.box((x,.48,z),(.08,.22,.08))
    receipt={ammo.name:ammo.save(),repair.name:repair.save()}
    (OUT/'new-models.json').write_text(json.dumps(receipt,indent=2)+'\n')

if __name__=='__main__':build()
