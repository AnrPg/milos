"use client";

import "maplibre-gl/dist/maplibre-gl.css";

import * as maplibregl from "maplibre-gl";
import { useEffect, useRef } from "react";

import { mapStyleUrl } from "@/lib/map-style";

export type Pin = { latitude: number; longitude: number };

// The worker ships as its own module next to the bundle.
maplibregl.setWorkerUrl(new URL("maplibre-gl/dist/maplibre-gl-worker.mjs", import.meta.url).href);

const ATHENS: [number, number] = [23.7275, 37.9838];

/**
 * The admin's pin for one location (plan §5a, board 3): drag it to the door,
 * or tap the map to drop it there. Each move reports the new point once.
 */
export default function LocationPinMap({
  pin,
  label,
  ariaLabel,
  onMove,
}: {
  pin: Pin | null;
  label: string;
  ariaLabel: string;
  onMove: (pin: Pin) => void;
}) {
  const container = useRef<HTMLDivElement>(null);
  const map = useRef<maplibregl.Map | null>(null);
  const marker = useRef<maplibregl.Marker | null>(null);
  const labelElement = useRef<HTMLSpanElement | null>(null);
  const onMoveRef = useRef(onMove);

  useEffect(() => {
    onMoveRef.current = onMove;
  });

  useEffect(() => {
    if (!container.current) return;
    let instance: maplibregl.Map;
    try {
      instance = new maplibregl.Map({
        container: container.current,
        style: mapStyleUrl(),
        center: ATHENS,
        zoom: 11,
        attributionControl: { compact: true },
      });
    } catch {
      // No WebGL2 (old devices, some test browsers): the page works without the map.
      return;
    }
    instance.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-right");
    instance.on("click", (event) => onMoveRef.current({ latitude: event.lngLat.lat, longitude: event.lngLat.lng }));
    map.current = instance;
    return () => {
      instance.remove();
      map.current = null;
      marker.current = null;
    };
  }, []);

  useEffect(() => {
    const instance = map.current;
    if (!instance) return;
    if (!pin) {
      marker.current?.remove();
      marker.current = null;
      return;
    }
    const at: [number, number] = [pin.longitude, pin.latitude];
    if (!marker.current) {
      const element = document.createElement("div");
      element.className = "palee-map-pin";
      element.dataset.selected = "true";
      const text = document.createElement("span");
      text.className = "palee-map-pin__label";
      const dot = document.createElement("span");
      dot.className = "palee-map-pin__dot";
      element.append(text, dot);
      labelElement.current = text;
      const created = new maplibregl.Marker({ element, anchor: "bottom", draggable: true }).setLngLat(at).addTo(instance);
      created.on("dragend", () => {
        const point = created.getLngLat();
        onMoveRef.current({ latitude: point.lat, longitude: point.lng });
      });
      marker.current = created;
      instance.jumpTo({ center: at, zoom: Math.max(instance.getZoom(), 16) });
    } else {
      const current = marker.current.getLngLat();
      if (current.lat !== pin.latitude || current.lng !== pin.longitude) {
        marker.current.setLngLat(at);
        if (!instance.getBounds().contains(at)) instance.easeTo({ center: at, zoom: Math.max(instance.getZoom(), 16) });
      }
    }
  }, [pin]);

  useEffect(() => {
    if (labelElement.current) labelElement.current.textContent = label;
  }, [label, pin]);

  return <div ref={container} role="region" aria-label={ariaLabel} className="h-full w-full" />;
}
