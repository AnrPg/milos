# Anatomy atlas: attribution

The 3D meshes in this folder (`muscles.glb`, `bones.glb`) come from
**anatomy-models** by Data Value Consulting and the original authors,
https://github.com/lucgrn3/anatomy-models, commit `ac52bab`
("models: anatomy 3d v1 meshes under cc by-sa 4.0").

They are licensed under the **Creative Commons Attribution-ShareAlike 4.0
International** licence (https://creativecommons.org/licenses/by-sa/4.0/,
legal code in `LICENSE`). Per-node source, licence and modification notes are
in `credits.json`. Anyone may reuse these files under the same licence.

## Upstream notices

- Z-Anatomy - The libre 3D atlas of anatomy - CC BY-SA 4.0 (Gauthier Kervyn, Marcin Zielinski). Models modified.
- BodyParts3D, (c) The Database Center for Life Science, licensed under CC BY-SA 2.1 Japan. Models modified.
- NIH 3D (3d.nih.gov), 'Human Skeleton' series by My Segmenter, CC BY 4.0. Meshes registered and modified.
- Sketchfab models under CC BY 4.0 by ebauer4 (Elon University), usf-idex-access3d (University of South Florida) and OSU.Multimedia (The Ohio State University). Meshes registered and modified.

## Changes made for Palee

- `muscles.glb`: the two middle-ear muscles derived from the Open Anatomy
  Project inner ear atlas (nodes `ta2-2102.l/.r` and `ta2-2103.l/.r`,
  distributed upstream under the 3D Slicer License) were removed, geometry
  included. No 3D Slicer-licensed content is distributed here, so the upstream
  `LICENSE-slicer.txt` is not included. All other meshes are unchanged.
- `index.json`: trimmed to the muscle nodes' centre, radius and bounding box.
- `credits.json`: the entries for the removed nodes and their source dropped.

Reproduce with `node scripts/anatomy/vendor-atlas.mjs <anatomy-models checkout> public/anatomy/v1`.
