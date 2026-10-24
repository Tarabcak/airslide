# AirPods geometry

“AirPods Pro” by JY_JY_, licensed under Creative Commons Attribution 4.0.
Original: https://sketchfab.com/3d-models/airpods-pro-4478dddbfa244f6f9b93eebbd027a73b
Licence: https://creativecommons.org/licenses/by/4.0/
Distribution source: https://sceneview.github.io/models/platforms/airpods_pro.glb
Source SHA256: 3dc5fe166ad944f7e47e0e4aa39806390f954be749635d8ea08677629fe8c5e2

Adaptations: removed case, separated earbuds, centered and reoriented geometry,
converted to native geometry arrays; simplified materials, omitted texture maps.
This is an AirPods Pro visual reference, not an exact Pro 3 CAD model.
Left/right selection describes the active motion sensor reported by Core Motion,
not a complete inventory of connected Bluetooth earbuds.

## Hand
Continuous right-hand mesh from the Immersive Web WebXR Input Profiles assets,
https://github.com/immersive-web/webxr-input-profiles/tree/main/packages/assets/profiles/generic-hand
MIT licence, reproduced in HAND-LICENSE.md. Adapted by baking a loose pinching grip,
reorienting and scaling the geometry, and replacing materials with neutral warm clay.
The illustrated hand is a grip guide, not hand tracking. Rebuild with
`scripts/prepare-hand.py` and the source right.glb.
