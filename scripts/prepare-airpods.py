"""Convert the attributed GLB's two earbud meshes to compact native geometry JSON.
Usage: python3 scripts/prepare-airpods.py /path/to/airpods_pro.glb
Source/licence: macos/Assets/CREDITS.md. Case omitted; centered, rotated, scaled.
"""
import base64, json, struct, sys
from pathlib import Path
b=Path(sys.argv[1]).read_bytes(); size=struct.unpack_from('<I',b,12)[0]
j=json.loads(b[20:20+size]); start=20+size; binary=b[start+8:]
def accessor(i):
 a=j['accessors'][i];v=j['bufferViews'][a['bufferView']]; count={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']];fmt={5126:'f',5123:'H',5125:'I',5121:'B'}[a['componentType']];width=struct.calcsize(fmt)*count;offset=v.get('byteOffset',0)+a.get('byteOffset',0)
 return [struct.unpack_from('<'+fmt*count,binary,offset+n*v.get('byteStride',width)) for n in range(a['count'])]
def pack(values,fmt):return base64.b64encode(struct.pack('<'+fmt*len(values),*values)).decode()
for side, ids in [('right',range(6)),('left',range(6,12))]:
 primitives=[p for i in ids for p in j['meshes'][i]['primitives']]
 allpos=[v for p in primitives for v in accessor(p['attributes']['POSITION'])]; center=[(min(v[k] for v in allpos)+max(v[k] for v in allpos))/2 for k in range(3)]
 result=[]
 for p in primitives:
  positions=[c for v in accessor(p['attributes']['POSITION']) for c in ((v[0]-center[0])*.72,-(v[2]-center[2])*.72,(v[1]-center[1])*.72)]
  normals=[c for v in accessor(p['attributes']['NORMAL']) for c in (v[0],-v[2],v[1])]
  indices=[v[0] for v in accessor(p['indices'])] if 'indices' in p else list(range(len(positions)//3))
  result.append(dict(positions=pack(positions,'f'),normals=pack(normals,'f'),indices=pack(indices,'I'),material=p['material']))
 for folder in ('macos/Assets/','relay/public/models/'): Path(folder+side+'.json').write_text(json.dumps(result,separators=(',',':')))
