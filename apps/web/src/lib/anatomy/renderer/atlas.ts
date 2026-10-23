/**
 * three.js side of the anatomy figure (ADR-164). Only ever reached through a
 * dynamic import, so three and the atlas stay out of the main bundle.
 */
import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import { MeshoptDecoder } from "three/examples/jsm/libs/meshopt_decoder.module.js";
import { RoomEnvironment } from "three/examples/jsm/environments/RoomEnvironment.js";

import {
  ATLAS_BASE_URL,
  parseAtlasNodeName,
  roleByTa2,
  type AnatomyHighlights,
  type AnatomyPalette,
  type AnatomyRole,
  type AtlasIndex,
} from "../figure";

export type Atlas = { muscles: THREE.Object3D; bones: THREE.Object3D };

let atlasPromise: Promise<Atlas> | null = null;
let indexPromise: Promise<AtlasIndex> | null = null;

function loadGlb(loader: GLTFLoader, url: string): Promise<THREE.Object3D> {
  return loader.loadAsync(url).then((gltf) => gltf.scene);
}

/** Loads both meshes once per page; every figure clones from them (geometry is shared). */
export function loadAtlas(): Promise<Atlas> {
  if (!atlasPromise) {
    const loader = new GLTFLoader();
    loader.setMeshoptDecoder(MeshoptDecoder);
    atlasPromise = Promise.all([
      loadGlb(loader, `${ATLAS_BASE_URL}/muscles.glb`),
      loadGlb(loader, `${ATLAS_BASE_URL}/bones.glb`),
    ]).then(([muscles, bones]) => {
      muscles.traverse((object) => {
        if (!(object as THREE.Mesh).isMesh) return;
        let named: THREE.Object3D | null = object;
        while (named && !parseAtlasNodeName(named.name)) named = named.parent;
        object.userData.ta2 = named ? parseAtlasNodeName(named.name)?.ta2 : undefined;
      });
      return { muscles, bones };
    });
    atlasPromise.catch(() => {
      atlasPromise = null;
    });
  }
  return atlasPromise;
}

export function loadAtlasIndex(): Promise<AtlasIndex> {
  if (!indexPromise) {
    indexPromise = fetch(`${ATLAS_BASE_URL}/index.json`).then((response) => {
      if (!response.ok) throw new Error(`atlas index ${response.status}`);
      return response.json() as Promise<AtlasIndex>;
    });
    indexPromise.catch(() => {
      indexPromise = null;
    });
  }
  return indexPromise;
}

/** Whole-body framing (metres, +Y up, facing +Z). */
export const BODY = { minY: 0.0, maxY: 1.71, halfWidth: 0.34, centerY: 0.86 };
export const FOV = 22;

export function bodyDistance(aspect: number): number {
  const tan = Math.tan(THREE.MathUtils.degToRad(FOV / 2));
  const halfHeight = ((BODY.maxY - BODY.minY) / 2) * 1.06;
  return Math.max(halfHeight / tan, (BODY.halfWidth * 1.1) / (tan * aspect));
}

/**
 * One figure: a cloned muscle + bone model, lights and materials. A renderer
 * (one WebGL context) draws it; the scene itself owns no GL state.
 */
export class AnatomyScene {
  readonly scene = new THREE.Scene();
  readonly model = new THREE.Group();
  readonly muscleMeshes: THREE.Mesh[] = [];
  private readonly boneMaterial = new THREE.MeshPhysicalMaterial({ roughness: 0.65 });
  private readonly baseMaterial = new THREE.MeshPhysicalMaterial({
    roughness: 0.55,
    sheen: 0.5,
    sheenColor: new THREE.Color(0xffe0d8),
    clearcoat: 0.2,
  });
  private readonly roleMaterials = new Map<string, THREE.MeshPhysicalMaterial>();
  private environment: THREE.Texture | null = null;
  private readonly lights: Array<{ light: THREE.DirectionalLight; base: THREE.Vector3 }>;
  private static readonly yAxis = new THREE.Vector3(0, 1, 0);

  /** Turns the lights with a camera that orbits the body by `yaw`. */
  orientLights(yaw: number) {
    for (const { light, base } of this.lights) light.position.copy(base).applyAxisAngle(AnatomyScene.yAxis, yaw);
  }

  constructor(atlas: Atlas) {
    const muscles = atlas.muscles.clone(true);
    const bones = atlas.bones.clone(true);
    bones.traverse((object) => {
      if ((object as THREE.Mesh).isMesh) (object as THREE.Mesh).material = this.boneMaterial;
    });
    muscles.traverse((object) => {
      const mesh = object as THREE.Mesh;
      if (!mesh.isMesh) return;
      mesh.material = this.baseMaterial;
      this.muscleMeshes.push(mesh);
    });
    this.model.add(bones, muscles);
    this.scene.add(this.model);

    // Key and rim light as in the approved render; they follow each camera (orientLights)
    // so the back view is lit like the front.
    this.lights = [
      { light: new THREE.DirectionalLight(0xffffff, 2.0), base: new THREE.Vector3(1, 2, 3) },
      { light: new THREE.DirectionalLight(0xbfd0ff, 0.9), base: new THREE.Vector3(-2, 1, -2) },
    ];
    for (const { light, base } of this.lights) {
      light.position.copy(base);
      this.scene.add(light);
    }
  }

  /** Image-based lighting; needs the renderer, once. */
  attachEnvironment(renderer: THREE.WebGLRenderer) {
    if (this.environment) return;
    const pmrem = new THREE.PMREMGenerator(renderer);
    this.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
    pmrem.dispose();
    this.scene.environment = this.environment;
    this.scene.environmentIntensity = 0.45;
  }

  private material(role: AnatomyRole, palette: AnatomyPalette, selected: boolean): THREE.MeshPhysicalMaterial {
    const key = `${role}:${selected ? 1 : 0}`;
    let material = this.roleMaterials.get(key);
    if (!material) {
      material = new THREE.MeshPhysicalMaterial({ roughness: 0.45, sheen: 0.4, clearcoat: 0.35 });
      this.roleMaterials.set(key, material);
    }
    material.color.set(palette[role]);
    material.emissive.set(selected ? palette[role] : 0x000000);
    material.emissiveIntensity = selected ? 0.35 : 0;
    return material;
  }

  private selectedBase: THREE.MeshPhysicalMaterial | null = null;

  /** Paints highlights; `selected` ta2 ids get a glow so a pick is visible. */
  paint(highlights: AnatomyHighlights, palette: AnatomyPalette, selected: ReadonlySet<string> = new Set()) {
    const roles = roleByTa2(highlights);
    this.baseMaterial.color.set(palette.base);
    this.boneMaterial.color.set(palette.bone);
    if (!this.selectedBase) this.selectedBase = this.baseMaterial.clone();
    this.selectedBase.color.set(palette.base);
    this.selectedBase.emissive.set(palette.base);
    this.selectedBase.emissiveIntensity = 0.45;
    for (const mesh of this.muscleMeshes) {
      const ta2 = mesh.userData.ta2 as string | undefined;
      const role = ta2 ? roles.get(ta2) : undefined;
      const isSelected = ta2 ? selected.has(ta2) : false;
      mesh.material = role ? this.material(role, palette, isSelected) : isSelected ? this.selectedBase : this.baseMaterial;
    }
  }

  dispose() {
    this.boneMaterial.dispose();
    this.baseMaterial.dispose();
    this.selectedBase?.dispose();
    for (const material of this.roleMaterials.values()) material.dispose();
    this.environment?.dispose();
  }
}

/** The browser could not make a WebGL context at all: the figure cannot render on this device. */
export class WebglUnavailableError extends Error {
  constructor(cause: unknown) {
    super("WebGL is unavailable", { cause });
    this.name = "WebglUnavailableError";
  }
}

/**
 * A WebGL renderer for the figure. Multisampling is the first thing a weak or
 * busy GPU (or a software one) refuses, so a context that cannot be made with
 * it is retried once without it; when that fails too, WebglUnavailableError.
 */
export function createRenderer(canvas?: HTMLCanvasElement, preserveDrawingBuffer = false): THREE.WebGLRenderer {
  let renderer: THREE.WebGLRenderer;
  try {
    renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, preserveDrawingBuffer });
  } catch {
    try {
      renderer = new THREE.WebGLRenderer({ canvas, antialias: false, alpha: true, preserveDrawingBuffer });
    } catch (error) {
      throw new WebglUnavailableError(error);
    }
  }
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.setClearColor(0x000000, 0);
  renderer.setScissorTest(true);
  return renderer;
}

/** Positions a camera on a circle around the body's vertical axis. */
export function placeCamera(camera: THREE.PerspectiveCamera, yaw: number, distance: number, target: THREE.Vector3) {
  camera.position.set(target.x + Math.sin(yaw) * distance, target.y + 0.05, target.z + Math.cos(yaw) * distance);
  camera.lookAt(target);
}
