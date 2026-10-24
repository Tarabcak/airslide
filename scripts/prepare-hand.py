"""Bake an MIT WebXR hand mesh into a loose presentation grip.
Usage: python3 scripts/prepare-hand.py right.glb (requires numpy).
Source: immersive-web/webxr-input-profiles, packages/assets/profiles/generic-hand.
"""
import base64, json, struct, sys
from pathlib import Path
import numpy as np
b=Path(sys.argv[1]).read_bytes(); size=struct.unpack_from('<I',b,12)[0]
j=json.loads(b[20:20+size]); binary=b[28+size:]
def acc(i):
 a=j['accessors'][i]; v=j['bufferViews'][a['bufferView']]
 n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
 dtype={5126:'<f4',5123:'<u2',5125:'<u4',5121:'u1'}[a['componentType']]
 return np.frombuffer(binary,dtype=dtype,count=a['count']*n,offset=v.get('byteOffset',0)+a.get('byteOffset',0)).reshape(-1,n)
def bend(p,angle):
 a=np.deg2rad(angle); r=np.array([[np.cos(a),-np.sin(a),0],[np.sin(a),np.cos(a),0],[0,0,1]])
 m=np.eye(4);m[:3,:3]=r;m[:3,3]=p-r@p;return m
transforms=np.tile(np.eye(4),(25,1,1))
for chain,angles in [([1,2,3,4],[0,-12,-15,0]),([5,6,7,8,9],[0,-40,-65,-35,0]),([10,11,12,13,14],[0,-65,-85,-50,0]),([15,16,17,18,19],[0,-70,-85,-50,0]),([20,21,22,23,24],[0,-75,-85,-50,0])]:
 parent=np.eye(4)
 for joint,angle in zip(chain,angles):
  p=np.array(j['nodes'][joint]['translation']); parent=parent@bend(p,angle);transforms[joint]=parent
# Oppose the thumb across the palm to pinch the stem against the index finger.
a,b=np.deg2rad([-33,12])
rx=np.array([[1,0,0],[0,np.cos(a),-np.sin(a)],[0,np.sin(a),np.cos(a)]])
ry=np.array([[np.cos(b),0,np.sin(b)],[0,1,0],[-np.sin(b),0,np.cos(b)]])
r=rx@ry;p=np.array(j['nodes'][1]['translation']);opposition=np.eye(4)
opposition[:3,:3]=r;opposition[:3,3]=p-r@p
for joint in [1,2,3,4]:transforms[joint]=opposition@transforms[joint]
pos=acc(0); norm=acc(1); joints=acc(3);weights=acc(4)
mats=(transforms[joints]*weights[:,:,None,None]).sum(axis=1)
posed=np.einsum('nij,nj->ni',mats,np.column_stack([pos,np.ones(len(pos))]))[:,:3]
norm=np.einsum('nij,nj->ni',mats[:,:3,:3],norm);norm/=np.linalg.norm(norm,axis=1)[:,None]
# Palm faces the viewer at a slight angle. Preserve a continuous mesh across knuckles.
rotation=np.array([[0,0,-1],[0,-1,0],[-1,0,0]])
posed=posed@rotation.T*19;norm=norm@rotation.T
# Place the pinching index and thumb around the earbud stem.
posed+=np.array([.15,-1.1,.0])
def pack(a,dtype):return base64.b64encode(np.asarray(a,dtype=dtype).tobytes()).decode()
Path('macos/Assets/hand.json').write_text(json.dumps([dict(positions=pack(posed,'<f4'),normals=pack(norm,'<f4'),indices=pack(acc(5),'<u4'),material=5)],separators=(',',':')))
print('hand bounds',posed.min(0),posed.max(0))
