// Apple devices open the map in Apple Maps, everyone else in Google Maps.
export const subscribeNever = () => () => undefined;
export const readApple = () => /Mac|iPhone|iPad|iPod/.test(navigator.userAgent);
export const serverApple = () => false;

export function mapsUrl(location: { latitude: number; longitude: number }, name: string, apple: boolean) {
  const at = `${location.latitude},${location.longitude}`;
  return apple
    ? `https://maps.apple.com/?ll=${at}&q=${encodeURIComponent(name)}`
    : `https://www.google.com/maps/search/?api=1&query=${at}`;
}

/** Directions by address when the gym never pinned its location. */
export function mapsSearchUrl(query: string, apple: boolean) {
  return apple
    ? `https://maps.apple.com/?q=${encodeURIComponent(query)}`
    : `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(query)}`;
}
