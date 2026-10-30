// Lucide line icons (ISC licence), copied in as SVG markup (plan §5a board 4 Q5).
// Amenity keys map to the icons board 4 settled; towels use their own icon, not `bath`.

export const AMENITY_ICONS: Record<string, string> = {
  showers: "<path d=\"m4 4 2.5 2.5\"/> <path d=\"M13.5 6.5a4.95 4.95 0 0 0-7 7\"/> <path d=\"M15 5 5 15\"/> <path d=\"M14 17v.01\"/> <path d=\"M10 16v.01\"/> <path d=\"M13 13v.01\"/> <path d=\"M16 10v.01\"/> <path d=\"M11 20v.01\"/> <path d=\"M17 14v.01\"/> <path d=\"M20 11v.01\"/>",
  changing_rooms: "<path d=\"M20.38 3.46 16 2a4 4 0 0 1-8 0L3.62 3.46a2 2 0 0 0-1.34 2.23l.58 3.47a1 1 0 0 0 .99.84H6v10c0 1.1.9 2 2 2h8a2 2 0 0 0 2-2V10h2.15a1 1 0 0 0 .99-.84l.58-3.47a2 2 0 0 0-1.34-2.23z\"/>",
  lockers: "<circle cx=\"12\" cy=\"16\" r=\"1\"/> <rect x=\"3\" y=\"10\" width=\"18\" height=\"12\" rx=\"2\"/> <path d=\"M7 10V7a5 5 0 0 1 10 0v3\"/>",
  towels: "<path d=\"M10 4 8 6\"/> <path d=\"M17 19v2\"/> <path d=\"M2 12h20\"/> <path d=\"M7 19v2\"/> <path d=\"M9 5 7.621 3.621A2.121 2.121 0 0 0 4 5v12a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-5\"/>",
  parking: "<rect width=\"18\" height=\"18\" x=\"3\" y=\"3\" rx=\"2\"/> <path d=\"M9 17V7h4a3 3 0 0 1 0 6H9\"/>",
  bike_parking: "<circle cx=\"18.5\" cy=\"17.5\" r=\"3.5\"/> <circle cx=\"5.5\" cy=\"17.5\" r=\"3.5\"/> <circle cx=\"15\" cy=\"5\" r=\"1\"/> <path d=\"M12 17.5V14l-3-3 4-3 2 3h2\"/>",
  public_transport_nearby: "<path d=\"M4 6 2 7\"/> <path d=\"M10 6h4\"/> <path d=\"m22 7-2-1\"/> <rect width=\"16\" height=\"16\" x=\"4\" y=\"3\" rx=\"2\"/> <path d=\"M4 11h16\"/> <path d=\"M8 15h.01\"/> <path d=\"M16 15h.01\"/> <path d=\"M6 19v2\"/> <path d=\"M18 21v-2\"/>",
  air_conditioning: "<path d=\"M6 12H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2\"/> <path d=\"M6 8h12\"/> <path d=\"M18.3 17.7a2.5 2.5 0 0 1-3.16 3.83 2.53 2.53 0 0 1-1.14-2V12\"/> <path d=\"M6.6 15.6A2 2 0 1 0 10 17v-5\"/>",
  sauna: "<path d=\"M12 9a4 4 0 0 0-2 7.5\"/> <path d=\"M12 3v2\"/> <path d=\"m6.6 18.4-1.4 1.4\"/> <path d=\"M20 4v10.54a4 4 0 1 1-4 0V4a2 2 0 0 1 4 0Z\"/> <path d=\"M4 13H2\"/> <path d=\"M6.34 7.34 4.93 5.93\"/>",
  cold_plunge: "<line x1=\"2\" x2=\"22\" y1=\"12\" y2=\"12\"/> <line x1=\"12\" x2=\"12\" y1=\"2\" y2=\"22\"/> <path d=\"m20 16-4-4 4-4\"/> <path d=\"m4 8 4 4-4 4\"/> <path d=\"m16 4-4 4-4-4\"/> <path d=\"m8 20 4-4 4 4\"/>",
  childcare: "<path d=\"M9 12h.01\"/> <path d=\"M15 12h.01\"/> <path d=\"M10 16c.5.3 1.2.5 2 .5s1.5-.2 2-.5\"/> <path d=\"M19 6.3a9 9 0 0 1 1.8 3.9 2 2 0 0 1 0 3.6 9 9 0 0 1-17.6 0 2 2 0 0 1 0-3.6A9 9 0 0 1 12 3c2 0 3.5 1.1 3.5 2.5s-.9 2.5-2 2.5c-.8 0-1.5-.4-1.5-1\"/>",
  wheelchair_accessible: "<circle cx=\"16\" cy=\"4\" r=\"1\"/> <path d=\"m18 19 1-7-6 1\"/> <path d=\"m5 8 3-3 5.5 3-2.36 3.5\"/> <path d=\"M4.24 14.5a5 5 0 0 0 6.88 6\"/> <path d=\"M13.76 17.5a5 5 0 0 0-6.88-6\"/>",
  accessible_restroom: "<path d=\"M7 12h13a1 1 0 0 1 1 1 5 5 0 0 1-5 5h-.598a.5.5 0 0 0-.424.765l1.544 2.47a.5.5 0 0 1-.424.765H5.402a.5.5 0 0 1-.424-.765L7 18\"/> <path d=\"M8 18a5 5 0 0 1-5-5V4a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v8\"/>",
  gender_neutral_restroom: "<path d=\"M18 21a8 8 0 0 0-16 0\"/> <circle cx=\"10\" cy=\"8\" r=\"5\"/> <path d=\"M22 20c0-3.37-2-6.5-4-8a5 5 0 0 0-.45-8.3\"/>",
  wifi: "<path d=\"M12 20h.01\"/> <path d=\"M2 8.82a15 15 0 0 1 20 0\"/> <path d=\"M5 12.859a10 10 0 0 1 14 0\"/> <path d=\"M8.5 16.429a5 5 0 0 1 7 0\"/>",
  water_refill: "<path d=\"M5.116 4.104A1 1 0 0 1 6.11 3h11.78a1 1 0 0 1 .994 1.105L17.19 20.21A2 2 0 0 1 15.2 22H8.8a2 2 0 0 1-2-1.79z\"/> <path d=\"M6 12a5 5 0 0 1 6 0 5 5 0 0 0 6 0\"/>",
  outdoor_area: "<path d=\"M10 10v.2A3 3 0 0 1 8.9 16H5a3 3 0 0 1-1-5.8V10a3 3 0 0 1 6 0Z\"/> <path d=\"M7 16v6\"/> <path d=\"M13 19v3\"/> <path d=\"M12 19h8.3a1 1 0 0 0 .7-1.7L18 14h.3a1 1 0 0 0 .7-1.7L16 9h.2a1 1 0 0 0 .8-1.7L13 3l-1.4 1.5\"/>",
  drop_in_friendly: "<path d=\"M13 4h3a2 2 0 0 1 2 2v14\"/> <path d=\"M2 20h3\"/> <path d=\"M13 20h9\"/> <path d=\"M10 12v.01\"/> <path d=\"M13 4.562v16.157a1 1 0 0 1-1.242.97L5 20V5.562a2 2 0 0 1 1.515-1.94l4-1A2 2 0 0 1 13 4.561Z\"/>",
};

export const UI_ICONS = {
  "map-pin": "<path d=\"M20 10c0 4.993-5.539 10.193-7.399 11.799a1 1 0 0 1-1.202 0C9.539 20.193 4 14.993 4 10a8 8 0 0 1 16 0\"/> <circle cx=\"12\" cy=\"10\" r=\"3\"/>",
  "clock": "<circle cx=\"12\" cy=\"12\" r=\"10\"/> <polyline points=\"12 6 12 12 16 14\"/>",
  "share": "<circle cx=\"18\" cy=\"5\" r=\"3\"/> <circle cx=\"6\" cy=\"12\" r=\"3\"/> <circle cx=\"18\" cy=\"19\" r=\"3\"/> <line x1=\"8.59\" x2=\"15.42\" y1=\"13.51\" y2=\"17.49\"/> <line x1=\"15.41\" x2=\"8.59\" y1=\"6.51\" y2=\"10.49\"/>",
  "x": "<path d=\"M18 6 6 18\"/> <path d=\"m6 6 12 12\"/>",
  "chevron-left": "<path d=\"m15 18-6-6 6-6\"/>",
  "chevron-right": "<path d=\"m9 18 6-6-6-6\"/>",
  "lock": "<rect width=\"18\" height=\"11\" x=\"3\" y=\"11\" rx=\"2\" ry=\"2\"/> <path d=\"M7 11V7a5 5 0 0 1 10 0v4\"/>",
  "images": "<path d=\"M18 22H4a2 2 0 0 1-2-2V6\"/> <path d=\"m22 13-1.296-1.296a2.41 2.41 0 0 0-3.408 0L11 18\"/> <circle cx=\"12\" cy=\"8\" r=\"2\"/> <rect width=\"16\" height=\"16\" x=\"6\" y=\"2\" rx=\"2\"/>",
  "check": "<path d=\"M20 6 9 17l-5-5\"/>",
  "message-circle": "<path d=\"M7.9 20A9 9 0 1 0 4 16.1L2 22Z\"/>",
} as const;

export type UiIcon = keyof typeof UI_ICONS;
