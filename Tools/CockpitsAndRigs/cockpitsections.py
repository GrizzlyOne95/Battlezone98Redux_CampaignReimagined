"""Attribute-preserving planar sections of source geometry; shared codecs own I/O."""
from collections import Counter
import numpy as np

def loops(faces,normal,distance):
    edges=Counter();points={}
    for face in faces:
        p=face[:,:3];keys=[tuple(np.rint(v*100000).astype(np.int64)) for v in p];points.update(zip(keys,p))
        for i in range(3):
            j=(i+1)%3
            if abs(np.dot(p[i],normal)-distance)<2e-6 and abs(np.dot(p[j],normal)-distance)<2e-6:edges[tuple(sorted((keys[i],keys[j])))]+=1
    border={e for e,count in edges.items() if count==1 and e[0]!=e[1]};adj={}
    for a,b in border:adj.setdefault(a,set()).add(b);adj.setdefault(b,set()).add(a)
    assert all(len(v)==2 for v in adj.values()),'section cut must have closed contours'
    result=[]
    while border:
        a,b=min(border);keys=[a];prev=a;cur=b;border.remove(tuple(sorted((a,b))))
        while cur!=a:
            keys.append(cur);nxt=next(v for v in adj[cur] if v!=prev);border.remove(tuple(sorted((cur,nxt))));prev,cur=cur,nxt
        result.append(np.array([points[k] for k in keys]))
    return result

def triangulate(p,normal):
    """Ear clipping of one simple planar contour, retaining boundary vertices."""
    p=np.asarray(p);drop=int(np.argmax(abs(normal)));q=np.delete(p,drop,axis=1);signed=sum(q[i,0]*q[(i+1)%len(q),1]-q[i,1]*q[(i+1)%len(q),0] for i in range(len(q)));sign=np.sign(signed);remaining=list(range(len(q)));result=[]
    def cross(a,b):return a[0]*b[1]-a[1]*b[0]
    while len(remaining)>3:
        found=False
        for k,b in enumerate(remaining):
            a,c=remaining[k-1],remaining[(k+1)%len(remaining)];A,B,C=q[[a,b,c]]
            if sign*cross(B-A,C-A)<1e-12:continue
            if any(min(sign*cross(B-A,q[j]-A),sign*cross(C-B,q[j]-B),sign*cross(A-C,q[j]-C))>=-1e-12 for j in remaining if j not in (a,b,c)):continue
            result.append([a,b,c]);remaining.pop(k);found=True;break
        assert found,'non-simple or degenerate section contour'
    result.append(remaining);indices=np.array(result)
    if np.dot(np.cross(p[indices[0,1]]-p[indices[0,0]],p[indices[0,2]]-p[indices[0,0]]),normal)<0:indices=indices[:,::-1]
    return indices

def section(data,indices,source_ids,planes,trim):
    faces=np.asarray(data,dtype=float)[indices.reshape(-1,3)];provenance=list(map(int,source_ids));audit=[]
    for normal,distance in planes:
        normal=np.array(normal,float);out=[];orig=[]
        for tri,source_id in zip(faces,provenance):
            polygon=list(tri)
            clipped=[]
            for i,a in enumerate(polygon):
                b=polygon[(i+1)%len(polygon)];da=np.dot(a[:3],normal)-distance;db=np.dot(b[:3],normal)-distance
                if da>=-1e-10:clipped.append(a)
                if (da>1e-10 and db<-1e-10) or (da<-1e-10 and db>1e-10):clipped.append(a+(b-a)*(da/(da-db)))
            for i in range(1,len(clipped)-1):
                face=np.array([clipped[0],clipped[i],clipped[i+1]])
                if np.linalg.norm(np.cross(face[1,:3]-face[0,:3],face[2,:3]-face[0,:3]))>1e-10:out.append(face);orig.append(source_id)
        faces=np.array(out);contours=loops(faces,normal,distance);caps=0
        for polygon in contours:
            n=-normal;axis=np.eye(3)[np.argmin(abs(n))];u=np.cross(n,axis);u/=np.linalg.norm(u);v=np.cross(n,u);uv=np.column_stack([polygon@u,polygon@v]);uv=(uv-uv.min(0))/np.maximum(np.ptp(uv,axis=0),1e-9);x0,y0,x1,y1=trim;uv=uv*np.array([x1-x0,y1-y0])+[x0,y0]
            rows=np.column_stack([polygon,np.tile(n,(len(polygon),1)),uv,np.tile(u,(len(polygon),1))]);tri=triangulate(polygon,n);out.extend(rows[tri]);orig.extend([-1]*len(tri));caps+=len(tri)
        faces=np.array(out);provenance=orig;audit.append(dict(normal=normal.tolist(),distance=distance,loops=len(contours),capTriangles=caps))
    # Interpolated shader bases remain orthonormal; original UV interpolation is exact.
    n=faces[:,:,3:6];n/=np.linalg.norm(n,axis=2)[:,:,None];t=faces[:,:,8:11];t-=n*(n*t).sum(2)[:,:,None];t/=np.maximum(np.linalg.norm(t,axis=2)[:,:,None],1e-12)
    result=[]
    for cap in (False,True):
        selected=faces[np.array(provenance)<0 if cap else np.array(provenance)>=0];rows=selected.reshape(-1,11).astype('<f4');result.append((rows,np.arange(len(rows),dtype='<u2')))
    return result[0],result[1],dict(cuts=audit,sourceTriangles=sorted({i for i in provenance if i>=0}),sourceFaceIds=[i for i in provenance if i>=0])
