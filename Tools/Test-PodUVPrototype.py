"""Narrow prototype checks: full UV replacement, no overlap, one material, exact geometry."""
from pathlib import Path
import hashlib,importlib.util,json,numpy as np,sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'Tools'))
spec=importlib.util.spec_from_file_location('pod',ROOT/'Tools/Build-PodUVPrototype.py');pod=importlib.util.module_from_spec(spec);spec.loader.exec_module(pod)
from bcdds import bc_dds_problem
from PIL import Image

def area(poly):
    if len(poly)<3:return 0.
    q=np.asarray(poly);r=np.roll(q,-1,axis=0)
    return float(abs(np.sum(q[:,0]*r[:,1]-q[:,1]*r[:,0]))*.5)

def overlap(subject,clip):
    q=np.asarray(clip);r=np.roll(q,-1,axis=0);sign=np.sign(np.sum(q[:,0]*r[:,1]-q[:,1]*r[:,0]))
    polygon=list(subject)
    for a,b in zip(q,r):
        def distance(v):return sign*((b[0]-a[0])*(v[1]-a[1])-(b[1]-a[1])*(v[0]-a[0]))
        if not polygon:break
        result=[];previous=polygon[-1];pd=distance(previous)
        for current in polygon:
            cd=distance(current)
            if (cd>=0)!=(pd>=0):result.append(previous+(current-previous)*(pd/(pd-cd)))
            if cd>=0:result.append(current)
            previous,pd=current,cd
        polygon=result
    return area(polygon)

def main():
    receipt=json.loads((pod.REF/'build.json').read_text());count=0
    for name,record in receipt.items():
        mesh=pod.p.read(pod.REF/(name+'.mesh'));original=pod.p.read(pod.p.SRC/(record['source']+'.mesh'))
        assert pod.p.geometry(mesh)==pod.p.geometry(original)==record['geometry'];count+=1
        assert len(mesh.submesh_list)==1 and mesh.submesh_list[0].material_name==name;count+=1
        assert mesh.skeleton_name==original.skeleton_name;count+=1
        sub=mesh.submesh_list[0];uv=pod.p.values(sub.vertex_data,pod.p.om.VES.TEXTURE_COORDINATES)[sub.index_array].reshape(-1,3,2)
        old=pod.p.values(original.submesh_list[0].vertex_data,pod.p.om.VES.TEXTURE_COORDINATES)[original.submesh_list[0].index_array].reshape(-1,3,2)
        assert uv.shape==old.shape and np.all(np.any(abs(uv-old)>1e-5,axis=(1,2))),'every source triangle must get fresh UVs';count+=1
        assert np.allclose(uv,record['uv'],atol=1e-7) and uv.min()>.005 and uv.max()<.995;count+=1
        assert all(area(t)>1e-8 for t in uv),'no collapsed UV faces';count+=len(uv)
        for i,t in enumerate(uv):
            for j in range(i):
                assert overlap(t,uv[j])<2e-7,(name,'overlapping faces',i,j,overlap(t,uv[j]))
                count+=1
        assert sum(len(c['triangles']) for c in record['charts'].values())==len(uv);count+=1
        assert hashlib.sha256((pod.p.SRC/(record['source']+'.mesh')).read_bytes()).hexdigest()==record['sourceMeshSha256'];count+=1
        assert hashlib.sha256((pod.REF/(name+'-master.png')).read_bytes()).hexdigest()==record['masterSha256'];count+=1
        assert bc_dds_problem((pod.REF/(name+'_d.dds')).read_bytes(),1024,1024) is None;count+=1
        print(name,': 100% remapped, no overlapping or collapsed triangles, exact geometry/rig retained.')
    new=json.loads((pod.REF/'new-models.json').read_text())
    assert set(new)=={'cramnew3','crhpnew3'};count+=1
    for name,record in new.items():
        path=pod.REF/(name+'.mesh');mesh=pod.p.read(path)
        assert hashlib.sha256(path.read_bytes()).hexdigest()==record['meshSha256'];count+=1
        assert mesh.skeleton_name is None and record['nativeCollisionAuthored'] is False;count+=1
        assert len(mesh.submesh_list)==record['batches']==2;count+=1
        triangles=0;points=[]
        for sub in mesh.submesh_list:
            pos=pod.p.values(sub.vertex_data,pod.p.om.VES.POSITION);points.extend(pos.tolist())
            normals=pod.p.values(sub.vertex_data,pod.p.om.VES.NORMAL)
            uv=pod.p.values(sub.vertex_data,pod.p.om.VES.TEXTURE_COORDINATES)
            assert np.isfinite(pos).all() and np.isfinite(normals).all() and np.isfinite(uv).all();count+=1
            assert np.allclose(np.linalg.norm(normals,axis=1),1,atol=1e-5);count+=1
            assert uv.min()>=0 and uv.max()<=1 and sub.index_array.max()<len(pos);count+=1
            for ids in sub.index_array.reshape(-1,3):
                a,b,c=pos[ids];assert np.linalg.norm(np.cross(b-a,c-a))>1e-7;count+=1;triangles+=1
        assert triangles==record['triangles']<1000;count+=1
        assert np.allclose([np.min(points,axis=0),np.max(points,axis=0)],record['bounds']);count+=1
        assert bc_dds_problem((pod.REF/(record['atlas']+'_d.dds')).read_bytes(),1024,1024) is None;count+=1
        text=(pod.REF/(name+'.material')).read_text();assert record['atlas']+'_d.dds' in text;count+=1
        print(name,': new authored geometry, finite UVs/normals, bounded size, two batches; render prototype only.')
    assert overlap(np.array([[0.,0.],[1.,0.],[0.,1.]]),np.array([[0.,0.],[1.,0.],[0.,1.]]))>.49;count+=1
    print('Pod UV prototype:',count,'checks passed')

if __name__=='__main__':main()
