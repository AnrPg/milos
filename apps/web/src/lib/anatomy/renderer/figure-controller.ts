import * as THREE from "three";

import {
  focusBounds,
  resolvePick,
  type AnatomyHighlights,
  type AnatomyPalette,
  type AnatomyPick,
  type AnatomyView,
} from "../figure";
import { muscleNode } from "../taxonomy";
import { AnatomyScene, BODY, FOV, bodyDistance, createRenderer, loadAtlas, loadAtlasIndex } from "./atlas";
import { drawViews, viewYaws, type Framing } from "./viewports";

export type FigureOptions = {
  highlights: AnatomyHighlights;
  view: AnatomyView;
  interactive: boolean;
  focus: string | null;
  palette: AnatomyPalette;
  reducedMotion: boolean;
  /** Present when the figure is pickable. */
  onPick: ((pick: AnatomyPick) => void) | null;
};

const MAX_ZOOM = 2.2;
const TAP_SLOP_PX = 6;
const TAP_MS = 600;
const TWEEN_MS = 650;

const ease = (t: number) => 1 - Math.pow(1 - t, 3);

/**
 * A live, optionally interactive figure: one canvas, one WebGL context, the
 * front and/or back figure drawn into viewports. Rotation is about the body's
 * vertical axis only, plus a mild zoom (with vertical pan while zoomed).
 * Renders on demand; a frame loop runs only while a camera move animates.
 */
export class FigureController {
  private readonly renderer: THREE.WebGLRenderer;
  private readonly scene: AnatomyScene;
  private readonly cameras = [new THREE.PerspectiveCamera(FOV, 0.5, 0.01, 20), new THREE.PerspectiveCamera(FOV, 0.5, 0.01, 20)];
  private readonly raycaster = new THREE.Raycaster();
  private readonly resizeObserver: ResizeObserver;
  private options: FigureOptions;
  private width = 1;
  private height = 1;
  private frame = 0;
  private disposed = false;

  // Framing the camera moves towards (goal) and is at (current).
  private goal: Framing = { yaw: 0, distance: 4.6, target: new THREE.Vector3(0, BODY.centerY, 0) };
  private current: Framing = { yaw: 0, distance: 4.6, target: new THREE.Vector3(0, BODY.centerY, 0) };
  private tween: { from: Framing; start: number } | null = null;
  private zoom = 1;
  private pick: AnatomyPick | null = null;
  private focusToken = 0;

  private readonly pointers = new Map<number, { x: number; y: number }>();
  private gesture: { x: number; y: number; at: number; moved: number; pinch: number | null } | null = null;

  constructor(
    private readonly container: HTMLElement,
    atlasScene: AnatomyScene,
    options: FigureOptions,
  ) {
    this.options = options;
    this.scene = atlasScene;
    this.renderer = createRenderer();
    this.scene.attachEnvironment(this.renderer);
    const canvas = this.renderer.domElement;
    canvas.style.display = "block";
    canvas.style.width = "100%";
    canvas.style.height = "100%";
    canvas.setAttribute("aria-hidden", "true");
    container.appendChild(canvas);

    canvas.addEventListener("pointerdown", this.onPointerDown);
    canvas.addEventListener("pointermove", this.onPointerMove);
    canvas.addEventListener("pointerup", this.onPointerUp);
    canvas.addEventListener("pointercancel", this.onPointerCancel);
    canvas.addEventListener("wheel", this.onWheel, { passive: false });
    container.addEventListener("keydown", this.onKeyDown);

    this.resizeObserver = new ResizeObserver(() => this.resize());
    this.resizeObserver.observe(container);
    this.resize();
    this.applyInteractivity();
    this.scene.paint(options.highlights, options.palette);
    this.reframe(false);
  }

  update(next: Partial<FigureOptions>) {
    const previous = this.options;
    this.options = { ...previous, ...next };
    if (next.interactive !== undefined && next.interactive !== previous.interactive) this.applyInteractivity();
    if (next.view !== undefined && next.view !== previous.view) this.reframe(false);
    if (next.focus !== undefined && next.focus !== previous.focus) this.reframe(true);
    this.repaint();
  }

  dispose() {
    this.disposed = true;
    cancelAnimationFrame(this.frame);
    this.resizeObserver.disconnect();
    const canvas = this.renderer.domElement;
    canvas.removeEventListener("pointerdown", this.onPointerDown);
    canvas.removeEventListener("pointermove", this.onPointerMove);
    canvas.removeEventListener("pointerup", this.onPointerUp);
    canvas.removeEventListener("pointercancel", this.onPointerCancel);
    canvas.removeEventListener("wheel", this.onWheel);
    this.container.removeEventListener("keydown", this.onKeyDown);
    this.scene.dispose();
    this.renderer.dispose();
    this.renderer.forceContextLoss();
    canvas.remove();
  }

  private applyInteractivity() {
    const canvas = this.renderer.domElement;
    const pickable = this.options.onPick != null;
    canvas.style.touchAction = this.options.interactive ? "none" : "auto";
    canvas.style.cursor = this.options.interactive ? "grab" : pickable ? "pointer" : "default";
  }

  private repaint() {
    const selected = new Set(this.pick ? (muscleNode(this.pick.nodeId)?.ta2Ids ?? []) : []);
    this.scene.paint(this.options.highlights, this.options.palette, selected);
    this.requestRender();
  }

  private resize() {
    const width = Math.max(1, this.container.clientWidth);
    const height = Math.max(1, this.container.clientHeight);
    if (width === this.width && height === this.height) return;
    this.width = width;
    this.height = height;
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    this.renderer.setSize(width, height, false);
    if (!this.options.focus) {
      this.goal.distance = this.fullDistance();
      if (!this.tween) this.current.distance = this.goal.distance;
    }
    this.requestRender();
  }

  private slotAspect() {
    return this.width / viewYaws(this.options.view).length / this.height;
  }

  private fullDistance() {
    return bodyDistance(this.slotAspect());
  }

  /** Frames the whole body, or the `focus` node using its bounds from the atlas index. */
  private reframe(animate: boolean) {
    const token = ++this.focusToken;
    const focus = this.options.focus;
    this.zoom = 1;
    if (!focus) {
      this.moveTo({ yaw: 0, distance: this.fullDistance(), target: new THREE.Vector3(0, BODY.centerY, 0) }, animate);
      return;
    }
    void loadAtlasIndex()
      .then((index) => {
        if (this.disposed || token !== this.focusToken) return;
        const bounds = focusBounds(focus, index);
        if (!bounds) return;
        const tan = Math.tan(THREE.MathUtils.degToRad(FOV / 2));
        const fit = Math.max(bounds.size[1] / 2, bounds.size[0] / 2 / this.slotAspect()) / tan;
        const distance = THREE.MathUtils.clamp(fit * 1.35 + bounds.size[2], 0.9, this.fullDistance());
        const yaw = this.options.view === "both" ? 0 : (bounds.posterior ? Math.PI : 0) - viewYaws(this.options.view)[0];
        const target = new THREE.Vector3(0, bounds.center[1], 0);
        this.moveTo({ yaw: wrapAngle(yaw, this.current.yaw), distance, target }, animate);
      })
      .catch(() => undefined);
  }

  private moveTo(goal: Framing, animate: boolean) {
    this.goal = goal;
    if (!animate || this.options.reducedMotion) {
      this.current = { yaw: goal.yaw, distance: goal.distance, target: goal.target.clone() };
      this.tween = null;
      this.requestRender();
      return;
    }
    this.tween = { from: { ...this.current, target: this.current.target.clone() }, start: performance.now() };
    this.requestRender();
  }

  private requestRender() {
    if (this.disposed || this.frame) return;
    this.frame = requestAnimationFrame(this.renderFrame);
  }

  private readonly renderFrame = (now: number) => {
    this.frame = 0;
    if (this.disposed) return;
    if (this.tween) {
      const t = Math.min(1, (now - this.tween.start) / TWEEN_MS);
      const k = ease(t);
      const { from } = this.tween;
      this.current = {
        yaw: from.yaw + (this.goal.yaw - from.yaw) * k,
        distance: from.distance + (this.goal.distance - from.distance) * k,
        target: from.target.clone().lerp(this.goal.target, k),
      };
      if (t >= 1) this.tween = null;
    }
    const framing = { ...this.current, distance: this.current.distance / this.zoom };
    drawViews(this.renderer, this.scene, this.cameras, this.options.view, framing, this.width, this.height);
    if (this.tween) this.requestRender();
  };

  // --- input ---------------------------------------------------------------

  private readonly onPointerDown = (event: PointerEvent) => {
    if (!this.options.interactive && !this.options.onPick) return;
    this.pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
    if (this.options.interactive) this.renderer.domElement.setPointerCapture?.(event.pointerId);
    this.gesture = { x: event.clientX, y: event.clientY, at: performance.now(), moved: 0, pinch: this.pinchDistance() };
  };

  private readonly onPointerMove = (event: PointerEvent) => {
    const last = this.pointers.get(event.pointerId);
    if (!last || !this.gesture) return;
    const dx = event.clientX - last.x;
    const dy = event.clientY - last.y;
    last.x = event.clientX;
    last.y = event.clientY;
    this.gesture.moved += Math.abs(dx) + Math.abs(dy);
    if (!this.options.interactive) return;
    if (this.pointers.size >= 2) {
      const distance = this.pinchDistance();
      if (distance && this.gesture.pinch) this.setZoom(this.zoom * (distance / this.gesture.pinch));
      this.gesture.pinch = distance;
      return;
    }
    this.tween = null;
    this.current.yaw += dx * 0.012;
    this.goal.yaw = this.current.yaw;
    if (this.zoom > 1) this.panBy(dy);
    this.requestRender();
  };

  private readonly onPointerUp = (event: PointerEvent) => {
    const gesture = this.gesture;
    this.pointers.delete(event.pointerId);
    if (this.pointers.size === 0) this.gesture = null;
    if (!gesture || this.pointers.size > 0) return;
    const isTap = gesture.moved < TAP_SLOP_PX && performance.now() - gesture.at < TAP_MS;
    if (isTap && this.options.onPick) this.pickAt(event.clientX, event.clientY);
  };

  private readonly onPointerCancel = (event: PointerEvent) => {
    this.pointers.delete(event.pointerId);
    if (this.pointers.size === 0) this.gesture = null;
  };

  private readonly onWheel = (event: WheelEvent) => {
    if (!this.options.interactive) return;
    event.preventDefault();
    this.setZoom(this.zoom * Math.exp(-event.deltaY * 0.0015));
  };

  private readonly onKeyDown = (event: KeyboardEvent) => {
    if (!this.options.interactive) return;
    const step = Math.PI / 12;
    if (event.key === "ArrowLeft") this.current.yaw -= step;
    else if (event.key === "ArrowRight") this.current.yaw += step;
    else if (event.key === "+" || event.key === "=") this.setZoom(this.zoom * 1.2);
    else if (event.key === "-") this.setZoom(this.zoom / 1.2);
    else return;
    event.preventDefault();
    this.tween = null;
    this.goal.yaw = this.current.yaw;
    this.requestRender();
  };

  private pinchDistance(): number | null {
    if (this.pointers.size < 2) return null;
    const [a, b] = [...this.pointers.values()];
    return Math.hypot(a.x - b.x, a.y - b.y);
  }

  private setZoom(zoom: number) {
    this.zoom = THREE.MathUtils.clamp(zoom, 1, MAX_ZOOM);
    if (this.zoom === 1 && !this.options.focus) this.current.target.y = BODY.centerY;
    this.requestRender();
  }

  private panBy(dyPixels: number) {
    const worldPerPixel = (2 * Math.tan(THREE.MathUtils.degToRad(FOV / 2)) * (this.current.distance / this.zoom)) / this.height;
    this.current.target.y = THREE.MathUtils.clamp(this.current.target.y + dyPixels * worldPerPixel, BODY.minY + 0.2, BODY.maxY - 0.2);
    this.goal.target.copy(this.current.target);
  }

  private pickAt(clientX: number, clientY: number) {
    const rect = this.renderer.domElement.getBoundingClientRect();
    const slots = viewYaws(this.options.view).length;
    const x = clientX - rect.left;
    const y = clientY - rect.top;
    const slotWidth = rect.width / slots;
    const slot = Math.min(slots - 1, Math.max(0, Math.floor(x / slotWidth)));
    const ndc = new THREE.Vector2(((x - slot * slotWidth) / slotWidth) * 2 - 1, -(y / rect.height) * 2 + 1);
    this.raycaster.setFromCamera(ndc, this.cameras[slot]);
    const hit = this.raycaster.intersectObject(this.scene.model, true)[0];
    const ta2 = hit?.object.userData.ta2 as string | undefined;
    if (!ta2) return;
    const pick = resolvePick(ta2, this.pick);
    if (!pick) return;
    this.pick = pick;
    this.repaint();
    this.options.onPick?.(pick);
  }
}

function wrapAngle(angle: number, near: number) {
  const turn = Math.PI * 2;
  return angle + Math.round((near - angle) / turn) * turn;
}

/** Loads the atlas (cached per page) and mounts a figure into `container`. */
export async function createFigure(container: HTMLElement, options: FigureOptions): Promise<FigureController> {
  const atlas = await loadAtlas();
  return new FigureController(container, new AnatomyScene(atlas), options);
}
