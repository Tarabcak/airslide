# Third-party notices

AirSlide's own code and its app icon (drawn by `scripts/make-icon.swift`) are MIT licensed, see `LICENSE`.
These bundled assets come from other authors and keep their own licences.

| Asset | Files | Author and licence | Changes |
|---|---|---|---|
| three.js r180 | `relay/public/vendor/three.module.min.js`, `relay/public/vendor/three.core.min.js` | three.js authors, MIT (`relay/public/vendor/THREE-LICENSE.txt`) | None |
| "AirPods Pro" 3D model | `macos/Assets/left.json`, `macos/Assets/right.json`, `relay/public/models/left.json`, `relay/public/models/right.json` | [JY_JY_ on Sketchfab](https://sketchfab.com/3d-models/airpods-pro-4478dddbfa244f6f9b93eebbd027a73b), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) | Case removed, earbuds separated, centred and reoriented, converted to geometry arrays, simplified materials, no textures (`scripts/prepare-airpods.py`) |
| Generic hand mesh | `macos/Assets/hand.json` | [Immersive Web WebXR Input Profiles](https://github.com/immersive-web/webxr-input-profiles/tree/main/packages/assets/profiles/generic-hand), MIT, Copyright 2019 Amazon (`macos/Assets/HAND-LICENSE.md`) | Baked into a pinching grip, reoriented, rescaled, neutral material (`scripts/prepare-hand.py`) |

Provenance details for the models are in `macos/Assets/CREDITS.md`.

AirPods is a trademark of Apple Inc. AirSlide is an independent project and is not affiliated with, sponsored or endorsed by Apple.
