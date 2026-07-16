import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Milos Training",
    short_name: "Milos",
    description: "Gym scheduling, athlete programming, and workout execution.",
    start_url: "/",
    display: "standalone",
    background_color: "#0b0d10",
    theme_color: "#c9ff45",
    orientation: "any",
    categories: ["fitness", "health", "sports"],
    icons: [
      { src: "/icon.svg", sizes: "any", type: "image/svg+xml", purpose: "any" },
      { src: "/icon-maskable.svg", sizes: "any", type: "image/svg+xml", purpose: "maskable" },
    ],
  };
}
