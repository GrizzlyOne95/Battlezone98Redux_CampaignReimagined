"""Surface-conforming faction bands using existing quiet paint atlas charts."""
import io
import numpy as np
import reddevilcockpit as shared

def clip(poly,axis,limit):
    """Keep dot(position, axis) <= limit, interpolating the source normal."""
    if not len(poly):return poly
    result=[];previous=poly[-1];a=float(np.dot(previous[:3],axis)-limit)
    for current in poly:
        b=float(np.dot(current[:3],axis)-limit)
        if (a<=0)!=(b<=0):result.append(previous+(current-previous)*(a/(a-b)))
        if b<=0:result.append(current)
        previous,a=current,b
    return np.array(result)

def geometry(body,origin,bones,faction):
    p=shared.values(body.vertex_data,shared.om.VES.POSITION);n=shared.values(body.vertex_data,shared.om.VES.NORMAL);tri=body.index_array.reshape(-1,3);assignments={}
    for a in body.bone_assignments():
        if a.weight>.99:assignments[a.vertex_index]=a.bone_index
    rows=[];indices=[];handles=[];provenance=[]
    # Charcoal base plus two worn red (Black Dog) or petrol (NSDF) slashes.
    # All coordinates are native hull coordinates, shared by 1P and 3P copies.
    layers=[('dark',1.08,1.38,.0015),('accent',1.15,1.31,.0025),('dark',1.65,1.95,.0015),('accent',1.72,1.88,.0025)]
    for index,t in enumerate(tri):
        bone=assignments.get(int(t[0]));q=p[t];normal=np.cross(q[1]-q[0],q[2]-q[0]);area=np.linalg.norm(normal)
        if bone not in bones or not all(assignments.get(int(v))==bone for v in t) or area<1e-9:continue
        normal/=area
        if normal[1]<.50:continue
        for sign in (-1,1):
            for kind,start,end,offset in layers:
                poly=np.column_stack([q,n[t]])
                # Forward hull rails only; don't paint glass, lights or guns.
                for axis,limit in [([-sign,0,0],-.60),([sign,0,0],2.05),([0,-1,0],-(origin[1]-.80)),([0,1,0],origin[1]+.10),([0,0,-1],-(origin[2]+.35)),([0,0,1],origin[2]+2.65),([sign*.25,0,1],origin[2]+end),([-sign*.25,0,-1],-(origin[2]+start))]:
                    poly=clip(poly,np.array(axis),limit)
                    if len(poly)<3:break
                if len(poly)<3:continue
                nn=poly[:,3:6];nn/=np.maximum(np.linalg.norm(nn,axis=1)[:,None],1e-9)
                # Same charts as cockpit paint, explicitly excluding optics.
                x0,y0,x1,y1=(.57,.86,.93,.96) if kind=='dark' else (.57,.695,.93,.780)
                u=np.clip((abs(poly[:,0])-.60)/1.45,0,1);v=np.clip((poly[:,2]-origin[2]+sign*.25*poly[:,0]-start)/(end-start),0,1)
                tangent=np.cross(nn,np.eye(3)[np.argmin(abs(nn),axis=1)]);tangent/=np.linalg.norm(tangent,axis=1)[:,None]
                data=np.column_stack([poly[:,:3]+nn*offset,nn,x0+(x1-x0)*u,y0+(y1-y0)*v,tangent]);first=len(rows)
                rows.extend(data.tolist());handles.extend([bone]*len(data))
                for j in range(1,len(poly)-1):
                    if np.linalg.norm(np.cross(data[j,:3]-data[0,:3],data[j+1,:3]-data[0,:3]))<1e-10:continue
                    indices.extend([first,first+j,first+j+1]);provenance.append(dict(sourceTriangle=index,bone=bone,layer=kind,offset=offset))
    assert indices,'no rail surfaces received faction markings'
    # Omit vertices unused by clipped degenerate polygon fans.
    used,remap=np.unique(indices,return_inverse=True)
    return np.array(rows,dtype='<f4')[used],remap.astype('<u2'),np.array(handles)[used],provenance

def model_bytes(mesh,data,indices,handles,material):
    """Append one paint batch through the shared Ogre serializer, keep all others."""
    sub=mesh.create_submesh();sub.material_name=material;sub.index_count=len(indices);sub.indices_32_bit=False;sub.set_index_buffer(indices.astype('<u2').tobytes());vd=sub.create_vertex_data(len(data))
    om=shared.om
    for typ,sem,offset in [(om.VET.FLOAT3,om.VES.POSITION,0),(om.VET.FLOAT3,om.VES.NORMAL,12),(om.VET.FLOAT2,om.VES.TEXTURE_COORDINATES,24),(om.VET.FLOAT3,om.VES.TANGENT,32)]:vd.vertex_declaration.create_vertex_element(0,typ,sem,offset,0)
    vd.create_vertex_buffer(data.astype('<f4').tobytes(),0,44)
    for i,bone in enumerate(handles):sub.create_bone_assignment(i,int(bone),1.)
    out=io.BytesIO();shared.oms.MeshSerializer(out).write(mesh);return out.getvalue()
