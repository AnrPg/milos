import * as THREE from "three";

import { highlightsKey, paletteKey, type AnatomyHighlights, type AnatomyPalette, type AnatomyView } from "../figure";
import { AnatomyScene, BODY, FOV, bodyDistance, createRenderer, loadAtlas } from "./atlas";
import { drawViews, viewYaws } from "./viewports";

/**
 * Static thumbnails for lists and cards. Every thumbnail on the page is drawn
 * by ONE offscreen renderer (one WebGL context), one at a time, and kept as a
 * PNG data URL memoised by view, size, palette and highlight set, so a feed
 * with many cards shows images, never many canvases.
 */
type Shared = { renderer: THREE.WebGLRenderer; scene: AnatomyScene; cameras: THREE.PerspectiveCamera[] };

let shared: Promise<Shared> | null = null;
let queue: Promise<unknown> = Promise.resolve();
const cache = new Map<string, Promise<string>>();
const CACHE_LIMIT = 300;

function getShared(): Promise<Shared> {
  if (!shared) {
    shared = loadAtlas().then((atlas) => {
      const canvas = document.createElement("canvas");
      const renderer = createRenderer(canvas, true);
      const scene = new AnatomyScene(atlas);
      scene.attachEnvironment(renderer);
      canvas.addEventListener("webglcontextlost", () => {
        shared = null;
        cache.clear();
      });
      return { renderer, scene, cameras: [new THREE.PerspectiveCamera(FOV), new THREE.PerspectiveCamera(FOV)] };
    });
    shared.catch(() => {
      shared = null;
    });
  }
  return shared;
}

export type ThumbRequest = {
  highlights: AnatomyHighlights;
  view: AnatomyView;
  /** CSS pixels. */
  width: number;
  height: number;
  palette: AnatomyPalette;
};

export function thumbKey(request: ThumbRequest, pixelRatio: number) {
  return [request.view, `${request.width}x${request.height}@${pixelRatio}`, paletteKey(request.palette), highlightsKey(request.highlights)].join("|");
}

export function renderThumb(request: ThumbRequest): Promise<string> {
  const pixelRatio = Math.min(window.devicePixelRatio || 1, 2);
  const key = thumbKey(request, pixelRatio);
  const hit = cache.get(key);
  if (hit) {
    cache.delete(key);
    cache.set(key, hit);
    return hit;
  }
  const job = queue.then(async () => {
    const { renderer, scene, cameras } = await getShared();
    renderer.setPixelRatio(pixelRatio);
    renderer.setSize(request.width, request.height, false);
    scene.paint(request.highlights, request.palette);
    const aspect = request.width / viewYaws(request.view).length / request.height;
    const framing = { yaw: 0, distance: bodyDistance(aspect), target: new THREE.Vector3(0, BODY.centerY, 0) };
    drawViews(renderer, scene, cameras, request.view, framing, request.width, request.height);
    return renderer.domElement.toDataURL("image/png");
  });
  queue = job.catch(() => undefined);
  cache.set(key, job);
  job.catch(() => cache.delete(key));
  while (cache.size > CACHE_LIMIT) cache.delete(cache.keys().next().value as string);
  return job;
}
