"""Offline skeleton deformation checks, not an evaluator of native game AI/servos."""
import math
import numpy as np
from bzmodellibs import legacy_port
import reddevilcockpit as shared

def world(skeleton,native_rotations=None,arm_pitch=0):
    result={};angle=math.radians(arm_pitch);c,ss=math.cos(angle),math.sin(angle);pitch=np.array([[1,0,0],[0,c,-ss],[0,ss,c]])
    def visit(b):
        if b.handle in result:return result[b.handle]
        q=b.orientation;r=np.array(legacy_port._quat_rotation(q.w,q.x,q.y,q.z))
        if native_rotations is not None:r=np.array(native_rotations.get(b.name,r))
        if b.name in ('age11tx1','age11tx2'):r=r@pitch
        mat=np.eye(4);mat[:3,:3]=r;mat[:3,3]=[b.position.x,b.position.y,b.position.z]
        if b.parent is not None:mat=visit(b.parent)@mat
        result[b.handle]=mat;return mat
    for b in skeleton.bones():visit(b)
    return result

def deformed(sub,skeleton,native_rotations,arm_pitch=0):
    bind=world(skeleton);posed=world(skeleton,native_rotations,arm_pitch);p=shared.values(sub.vertex_data,shared.om.VES.POSITION);n=shared.values(sub.vertex_data,shared.om.VES.NORMAL);pp=np.zeros_like(p);nn=np.zeros_like(n)
    for a in sub.bone_assignments():
        T=posed[a.bone_index]@np.linalg.inv(bind[a.bone_index]);pp[a.vertex_index]+=(T[:3,:3]@p[a.vertex_index]+T[:3,3])*a.weight;nn[a.vertex_index]+=(T[:3,:3]@n[a.vertex_index])*a.weight
    nn/=np.linalg.norm(nn,axis=1)[:,None]
    return pp,nn
