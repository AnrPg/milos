// ADR-175: recordings leave the device as 16 kHz mono 16-bit WAV, a format
// every speech-to-text provider accepts, whatever the browser recorded in
// (WebM/Opus on Chrome and Android, MP4/AAC on Safari and iOS).

export const TARGET_SAMPLE_RATE = 16_000;

/** Mixes channels to mono and resamples (linear) to `targetRate`. */
export function toMono16k(channels: Float32Array[], sourceRate: number, targetRate = TARGET_SAMPLE_RATE): Float32Array {
  if (channels.length === 0 || channels[0].length === 0) return new Float32Array(0);
  const length = channels[0].length;
  const mono = new Float32Array(length);
  for (const channel of channels) {
    for (let index = 0; index < length; index += 1) mono[index] += (channel[index] ?? 0) / channels.length;
  }
  if (sourceRate === targetRate) return mono;

  const ratio = sourceRate / targetRate;
  const outLength = Math.max(1, Math.floor(length / ratio));
  const out = new Float32Array(outLength);
  for (let index = 0; index < outLength; index += 1) {
    const position = index * ratio;
    const left = Math.floor(position);
    const right = Math.min(left + 1, length - 1);
    const weight = position - left;
    out[index] = mono[left] * (1 - weight) + mono[right] * weight;
  }
  return out;
}

/** A PCM WAV file (16-bit little endian) from mono samples in [-1, 1]. */
export function encodeWav(samples: Float32Array, sampleRate = TARGET_SAMPLE_RATE): Uint8Array {
  const bytes = new Uint8Array(44 + samples.length * 2);
  const view = new DataView(bytes.buffer);
  const writeText = (offset: number, text: string) => {
    for (let index = 0; index < text.length; index += 1) view.setUint8(offset + index, text.charCodeAt(index));
  };

  writeText(0, "RIFF");
  view.setUint32(4, 36 + samples.length * 2, true);
  writeText(8, "WAVE");
  writeText(12, "fmt ");
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true); // PCM
  view.setUint16(22, 1, true); // mono
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * 2, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, 16, true);
  writeText(36, "data");
  view.setUint32(40, samples.length * 2, true);

  for (let index = 0; index < samples.length; index += 1) {
    const clamped = Math.max(-1, Math.min(1, samples[index]));
    view.setInt16(44 + index * 2, clamped < 0 ? clamped * 0x8000 : clamped * 0x7fff, true);
  }
  return bytes;
}

export function toBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let index = 0; index < bytes.length; index += chunk) {
    binary += String.fromCharCode(...bytes.subarray(index, index + chunk));
  }
  return btoa(binary);
}
