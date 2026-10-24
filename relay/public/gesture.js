import * as THREE from './vendor/three.module.min.js';

// Optional visual feedback: failure must never interrupt slide navigation.
const reduced = matchMedia('(prefers-reduced-motion: reduce)');
// "AirPods Pro" by JY_JY_ (https://sketchfab.com/3d-models/airpods-pro-4478dddbfa244f6f9b93eebbd027a73b),
// CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/). Adapted meshes; see relay/public/models/CREDITS.md.
let renderer, scene, camera, root, canvas, frame = 0, generation = 0;
const models = new Map();
const clamp = x => Math.max(0, Math.min(1, x));
const smooth = x => { x = clamp(x); return x*x*(3-2*x); };
const decode = (text, Type) => {
  const bytes = Uint8Array.from(atob(text), c => c.charCodeAt(0));
  return new Type(bytes.buffer);
};
async function model(side) {
  if (!models.has(side)) models.set(side, fetch(`/_airslide/models/${side}.json`).then(r => {
    if (!r.ok) throw new Error('Model unavailable'); return r.json();
  }).then(parts => {
    const group = new THREE.Group();
    for (const part of parts) {
      const geometry = new THREE.BufferGeometry();
      geometry.setAttribute('position',new THREE.BufferAttribute(decode(part.positions,Float32Array),3));
      geometry.setAttribute('normal',new THREE.BufferAttribute(decode(part.normals,Float32Array),3));
      geometry.setIndex(new THREE.BufferAttribute(decode(part.indices,Uint32Array),1));
      const material = new THREE.MeshStandardMaterial({color:[0,3].includes(part.material) ? 0x131921 : 0xf5f8ff, roughness:part.material === 1 ? 0.6 : 0.24, metalness:part.material === 4 ? 0.65 : 0.07, transparent:true, side:THREE.DoubleSide});
      group.add(new THREE.Mesh(geometry,material));
    }
    return group;
  }));
  return models.get(side);
}
function initialize() {
  if (renderer) return;
  canvas = document.createElement('canvas'); canvas.setAttribute('aria-hidden','true');
  canvas.style.cssText='position:fixed;left:50%;bottom:8px;transform:translateX(-50%);width:min(540px,94vw);height:230px;pointer-events:none;z-index:9998;opacity:0';
  renderer = new THREE.WebGLRenderer({canvas,alpha:true,antialias:true});
  renderer.setPixelRatio(Math.min(devicePixelRatio,2)); renderer.setSize(540,230,false);
  renderer.setClearColor(0x000000,0); renderer.outputColorSpace=THREE.SRGBColorSpace;
  renderer.toneMapping=THREE.ACESFilmicToneMapping; renderer.toneMappingExposure=1.3;
  scene=new THREE.Scene(); camera=new THREE.PerspectiveCamera(32,540/230,0.1,50); camera.position.set(0,0,9);
  scene.add(new THREE.HemisphereLight(0xdceeff,0x24354f,2.6));
  for (const [color,power,x,y,z] of [[0xffffff,5,3,5,6],[0x9abfff,4,-4,1,2],[0x8fffd7,3,1,-1,-3]]) {
    const light=new THREE.DirectionalLight(color,power); light.position.set(x,y,z); scene.add(light);
  }
  root=new THREE.Group(); scene.add(root); document.body.append(canvas);
}
async function play({direction,side,duration=1250,scale=0.4}) {
  if (!['next','prev'].includes(direction) || !['left','right'].includes(side)) return;
  const current=++generation;
  cancelAnimationFrame(frame);
  if (canvas) canvas.style.opacity='0';
  try {
    const earbud=await model(side);
    if (current !== generation || document.hidden) return;
    initialize(); root.clear(); root.add(earbud);
    const sign=direction==='next'?1:-1;
    duration=Math.max(650,Math.min(2400,Number(duration)||1250));
    scale=Math.max(0.4,Math.min(1.3,Number(scale)||0.4));
    const started=performance.now();
    function animate(now) {
      const t=clamp((now-started)/duration);
      const travel=1-Math.pow(1-t,3); // quick arrival, long polished settle
      const opacity=smooth(t/0.17)*(1-smooth((t-0.67)/0.33));
      root.scale.setScalar(scale*(0.88+0.12*Math.sin(Math.PI*t)));
      root.position.set(reduced.matches?0:sign*(-2.5+5*travel),reduced.matches?0:Math.sin(t*Math.PI)*0.35-0.2,0);
      root.rotation.set(0.08+(reduced.matches?0:Math.sin(t*Math.PI)*0.08),
        (side==='left'?-0.45:0.45)+(reduced.matches?0:sign*(-0.35+0.7*travel)),
        reduced.matches?0:sign*(-0.10+0.20*travel));
      canvas.style.opacity=String(opacity); renderer.render(scene,camera);
      if (t<1 && current===generation) frame=requestAnimationFrame(animate);
      else canvas.style.opacity='0';
    }
    frame=requestAnimationFrame(animate);
  } catch { if (canvas) canvas.style.opacity='0'; }
}
window.addEventListener('airslide-gesture', event => play(event.detail || {}));
document.addEventListener('visibilitychange',()=>{ if(document.hidden){generation++;cancelAnimationFrame(frame);if(canvas)canvas.style.opacity='0';} });
// Warm geometry only; don't create a WebGL context until a gesture is shown.
for(const side of ['left','right']) model(side).catch(()=>{});

// Clean local rehearsal: real deck, no controls or overlay copy. Never active on the public host.
if (['127.0.0.1','localhost'].includes(location.hostname) && new URLSearchParams(location.search).has('airslide-preview')) {
  const side = new URLSearchParams(location.search).get('airslide-preview') === 'left' ? 'left' : 'right';
  document.addEventListener('keydown', event => {
    if (!event.isTrusted || event.repeat || !['ArrowLeft','ArrowRight'].includes(event.key)) return;
    play({direction:event.key === 'ArrowRight' ? 'next' : 'prev', side});
  });
}
