import * as THREE from "three";

import type { AnatomyView } from "../figure";
import { AnatomyScene, placeCamera } from "./atlas";

/** Yaw of each drawn figure: `both` draws front and back side by side in one canvas (one WebGL context). */
export function viewYaws(view: AnatomyView): number[] {
  if (view === "both") return [0, Math.PI];
  return [view === "back" ? Math.PI : 0];
}

export type Framing = { yaw: number; distance: number; target: THREE.Vector3 };

/** Draws one figure per view into side-by-side viewports of the renderer's canvas. */
export function drawViews(
  renderer: THREE.WebGLRenderer,
  scene: AnatomyScene,
  cameras: THREE.PerspectiveCamera[],
  view: AnatomyView,
  framing: Framing,
  width: number,
  height: number,
) {
  const yaws = viewYaws(view);
  const slot = width / yaws.length;
  renderer.setScissor(0, 0, width, height);
  renderer.setViewport(0, 0, width, height);
  renderer.clear();
  yaws.forEach((yaw, i) => {
    const camera = cameras[i];
    camera.aspect = slot / height;
    camera.updateProjectionMatrix();
    placeCamera(camera, yaw + framing.yaw, framing.distance, framing.target);
    scene.orientLights(yaw + framing.yaw);
    renderer.setViewport(i * slot, 0, slot, height);
    renderer.setScissor(i * slot, 0, slot, height);
    renderer.render(scene.scene, camera);
  });
}
