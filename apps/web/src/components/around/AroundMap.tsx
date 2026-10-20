"use client";

import "maplibre-gl/dist/maplibre-gl.css";

import * as maplibregl from "maplibre-gl";
import { useEffect, useRef } from "react";

import type { AroundPin, AroundViewport } from "@/api/around";
import { mapStyleUrl } from "@/lib/map-style";

// The worker ships as its own module next to the bundle.
maplibregl.setWorkerUrl(new URL("maplibre-gl/dist/maplibre-gl-worker.mjs", import.meta.url).href);

export type MapPin = AroundPin & { label: string };

const viewportOf = (map: maplibregl.Map): AroundViewport => {
  const bounds = map.getBounds();
  return { west: bounds.getWest(), south: bounds.getSouth(), east: bounds.getEast(), north: bounds.getNorth() };
};

type Markers = Map<string, { marker: maplibregl.Marker; element: HTMLElement }>;

/** The picked pin grows and sits on top. */
function markSelected(markers: Markers, selectedId: string | null) {
  for (const [id, entry] of markers) {
    entry.element.dataset.selected = String(id === selectedId);
    entry.element.style.zIndex = id === selectedId ? "2" : "";
  }
}

/**
 * The Γύρω μου map (board 9 Q3 B): the same MapLibre street map as the
 * location picker, with a pin per result (events round, boxes square).
 * Pins are pointer targets only; the list under the map is the keyboard and
 * screen-reader path, so the map never holds focus hostage.
 */
export default function AroundMap({
  pins,
  selectedId,
  initialViewport,
  ariaLabel,
  expanded,
  onSelect,
  onMoved,
  onFailed,
}: {
  pins: MapPin[];
  selectedId: string | null;
  initialViewport: AroundViewport;
  ariaLabel: string;
  /** The panel is full screen; the map redraws at its new size when this changes. */
  expanded: boolean;
  onSelect: (id: string) => void;
  onMoved: (viewport: AroundViewport) => void;
  onFailed: () => void;
}) {
  const container = useRef<HTMLDivElement>(null);
  const map = useRef<maplibregl.Map | null>(null);
  const markers = useRef<Markers>(new Map());
  const callbacks = useRef({ onSelect, onMoved, onFailed });
  const first = useRef(initialViewport);

  useEffect(() => {
    callbacks.current = { onSelect, onMoved, onFailed };
  });

  useEffect(() => {
    if (!container.current) return;
    let instance: maplibregl.Map;
    try {
      const { west, south, east, north } = first.current;
      instance = new maplibregl.Map({
        container: container.current,
        style: mapStyleUrl(),
        bounds: [
          [west, south],
          [east, north],
        ],
        attributionControl: { compact: true },
      });
    } catch {
      // No WebGL (old devices, some test browsers): the list still has everything.
      callbacks.current.onFailed();
      return;
    }
    instance.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-right");
    // Only the person's own panning or zooming offers «Ψάξε εδώ».
    let byPerson = false;
    const started = (event: { originalEvent?: unknown }) => {
      if (event.originalEvent) byPerson = true;
    };
    instance.on("dragstart", started);
    instance.on("zoomstart", started);
    instance.on("rotatestart", started);
    instance.on("moveend", (event) => {
      if (!byPerson && !(event as { originalEvent?: unknown }).originalEvent) return;
      byPerson = false;
      callbacks.current.onMoved(viewportOf(instance));
    });
    instance.on("error", () => undefined);
    map.current = instance;
    const current = markers.current;
    return () => {
      instance.remove();
      map.current = null;
      current.clear();
    };
  }, []);

  useEffect(() => {
    map.current?.resize();
  }, [expanded]);

  useEffect(() => {
    const instance = map.current;
    if (!instance) return;
    const next = new Set(pins.map((pin) => pin.id));
    for (const [id, entry] of markers.current) {
      if (!next.has(id)) {
        entry.marker.remove();
        markers.current.delete(id);
      }
    }
    for (const pin of pins) {
      if (markers.current.has(pin.id)) continue;
      const element = document.createElement("button");
      element.type = "button";
      element.tabIndex = -1;
      element.classList.add("milos-map-pin", "milos-around-pin");
      element.dataset.kind = pin.kind;
      element.dataset.pinId = pin.id;
      element.setAttribute("aria-label", pin.label);
      element.title = pin.label;
      const dot = document.createElement("span");
      dot.className = "milos-map-pin__dot";
      element.append(dot);
      element.addEventListener("click", (event) => {
        event.stopPropagation();
        callbacks.current.onSelect(pin.id);
      });
      const marker = new maplibregl.Marker({ element, anchor: "bottom" }).setLngLat([pin.longitude, pin.latitude]).addTo(instance);
      markers.current.set(pin.id, { marker, element });
    }
  }, [pins]);

  useEffect(() => {
    const instance = map.current;
    markSelected(markers.current, selectedId);
    const picked = selectedId ? markers.current.get(selectedId) : undefined;
    if (instance && picked && !instance.getBounds().contains(picked.marker.getLngLat())) {
      instance.easeTo({ center: picked.marker.getLngLat() });
    }
  }, [selectedId, pins]);

  return <div ref={container} role="region" aria-label={ariaLabel} className="h-full w-full" />;
}
