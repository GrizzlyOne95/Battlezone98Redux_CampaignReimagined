"""Synthetic clipping contracts independent of authored vehicle receipts."""
from collections import Counter
import numpy as np
import cockpitsections as cp

checks=0
def check(ok,label):
    global checks
    assert ok,label
    checks+=1

rows=[];indices=[]
for axis in range(3):
    u=np.eye(3)[(axis+1)%3];v=np.eye(3)[(axis+2)%3]
    for sign in (-1,1):
        n=np.eye(3)[axis]*sign;p=np.array([n-u-v,n+u-v,n+u+v,n-u+v]);start=len(rows)
        if sign<0:p=p[::-1]
        for point in p:rows.append([*point,*n,(point[0]+1)*.5,(point[1]+1)*.5,*u])
        indices.extend([start,start+1,start+2,start,start+2,start+3])
raw=np.array(rows,float);ix=np.array(indices);trim=(.1,.2,.3,.4)
surface,backs,audit=cp.section(raw,ix,np.arange(12),[([0,0,1],.2),([1,0,0],-.3)],trim)
triangles=np.concatenate([a[0][:,:3][a[1].reshape(-1,3)] for a in (surface,backs)]);edges=Counter()
for face in triangles:
    keys=[tuple(np.round(v,5)) for v in face]
    for i in range(3):edges[tuple(sorted((keys[i],keys[(i+1)%3])))]+=1
check(set(edges.values())=={2},'two successive cuts and caps form a watertight solid')
check(all(cut['loops']==1 and cut['capTriangles']>0 for cut in audit['cuts']),'each new cutting contour capped')
check(np.allclose(triangles.reshape(-1,3).min(0),[-.3,-1,.2]) and np.allclose(triangles.reshape(-1,3).max(0),[1,1,1]),'exact retained halfspaces, no source fit')
area=np.linalg.norm(np.cross(triangles[:,1]-triangles[:,0],triangles[:,2]-triangles[:,0]),axis=1)*.5
check(abs(area.sum()-2*(1.3*2+1.3*.8+2*.8))<1e-5,'closed clipped-box surface area, no doubled cap fill')
check((area>1e-10).all(),'no zero-area cap triangles')
surface_uv=surface[0][:,6:8];check(np.allclose(surface_uv[:,0],(surface[0][:,0]+1)*.5) and np.allclose(surface_uv[:,1],(surface[0][:,1]+1)*.5),'source UVs interpolate with position through both cuts')
uv=backs[0][:,6:8];check((uv>=[trim[0]-1e-6,trim[1]-1e-6]).all() and (uv<=[trim[2]+1e-6,trim[3]+1e-6]).all(),'quiet trim cap UVs stay in allocation')
for material in (surface,backs):
    d=material[0];check(np.isfinite(d).all(),'finite attributes');check(np.allclose(np.linalg.norm(d[:,3:6],axis=1),1),'normalized source/cap normals')
    check(np.allclose(np.linalg.norm(d[:,8:11],axis=1),1) and abs((d[:,3:6]*d[:,8:11]).sum(1)).max()<1e-6,'orthonormal interpolated tangent bases')
_,no_caps,_=cp.section(raw,ix,np.arange(12),[],trim);check(len(no_caps[0])==0,'no cuts add no cap geometry')
# Deliberately missing one side must not be silently repaired as a valid cut.
failed=False
try:cp.section(raw,ix[6:],np.arange(2,12),[([0,0,1],.2)],trim)
except AssertionError:failed=True
check(failed,'open input contour fails closed')
print('COCKPIT_SECTIONS_PASS',checks)
