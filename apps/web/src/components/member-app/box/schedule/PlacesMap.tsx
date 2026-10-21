"use client";

import "maplibre-gl/dist/maplibre-gl.css";

import * as maplibregl from "maplibre-gl";
import { useEffect, useRef } from "react";

import { mapStyleUrl } from "@/lib/map-style";

export type MapPlace = { id: string; name: string; latitude: number; longitude: number; selected: boolean };
export type MapBounds = { west: number; south: number; east: number; north: number };

// The worker ships as its own module next to the bundle.
maplibregl.setWorkerUrl(new URL("maplibre-gl/dist/maplibre-gl-worker.mjs", import.meta.url).href);

/**
 * A street map with the gym's name over each pin (plan §5a decision 6).
 * Reports the visible frame so the list can show «Σε αυτή την περιοχή».
 */
export default function PlacesMap({
  places,
  ariaLabel,
  onBoundsChange,
  onSelect,
}: {
  places: MapPlace[];
  ariaLabel: string;
  onBoundsChange: (bounds: MapBounds) => void;
  onSelect: (id: string) => void;
}) {
  const container = useRef<HTMLDivElement>(null);
  const map = useRef<maplibregl.Map | null>(null);
  const markers = useRef<maplibregl.Marker[]>([]);
  const fitted = useRef(false);
  const callbacks = useRef({ onBoundsChange, onSelect });

  useEffect(() => {
    callbacks.current = { onBoundsChange, onSelect };
  });

  useEffect(() => {
    if (!container.current) return;
    const instance = new maplibregl.Map({
      container: container.current,
      style: mapStyleUrl(),
      center: [23.7275, 37.9838],
      zoom: 11,
      attributionControl: { compact: true },
    });
    const report = () => {
      const bounds = instance.getBounds();
      callbacks.current.onBoundsChange({
        west: bounds.getWest(),
        south: bounds.getSouth(),
        east: bounds.getEast(),
        north: bounds.getNorth(),
      });
    };
    instance.on("moveend", report);
    instance.on("load", report);
    map.current = instance;
    return () => {
      instance.remove();
      map.current = null;
    };
  }, []);

  useEffect(() => {
    const instance = map.current;
    if (!instance) return;
    markers.current.forEach((marker) => marker.remove());
    markers.current = places.map((place) => {
      const element = document.createElement("button");
      element.type = "button";
      element.className = "milos-map-pin";
      element.dataset.selected = String(place.selected);
      element.setAttribute("aria-label", place.name);
      const label = document.createElement("span");
      label.className = "milos-map-pin__label";
      label.textContent = place.name;
      const dot = document.createElement("span");
      dot.className = "milos-map-pin__dot";
      element.append(label, dot);
      element.addEventListener("click", () => callbacks.current.onSelect(place.id));
      return new maplibregl.Marker({ element, anchor: "bottom" })
        .setLngLat([place.longitude, place.latitude])
        .addTo(instance);
    });

    if (!fitted.current && places.length > 0) {
      fitted.current = true;
      const selected = places.find((place) => place.selected) ?? places[0];
      const bounds = new maplibregl.LngLatBounds();
      places.forEach((place) => bounds.extend([place.longitude, place.latitude]));
      if (places.length === 1) instance.jumpTo({ center: [selected.longitude, selected.latitude], zoom: 14 });
      else instance.fitBounds(bounds, { padding: 64, maxZoom: 14, duration: 0 });
    }
  }, [places]);

  return <div ref={container} role="region" aria-label={ariaLabel} className="h-full w-full" />;
}
