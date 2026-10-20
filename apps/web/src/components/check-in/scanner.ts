"use client";

/**
 * Where the desk's scanner gets codes from (ADR-155 §7). The camera source
 * uses the browser's `BarcodeDetector` where it exists and the `jsqr`
 * decoder elsewhere (loaded only when needed). A test can put its own
 * source on `window.__milosScannerSource` before the page loads; nothing in
 * the app sets it.
 */
export type StopScanner = () => void;
export type ScannerSource = {
  start: (video: HTMLVideoElement, onCode: (text: string) => void) => Promise<StopScanner>;
};

export class CameraError extends Error {
  constructor(readonly reason: "denied" | "missing" | "unsupported" | "failed") {
    super(reason);
    this.name = "CameraError";
  }
}

type Detector = { detect: (source: CanvasImageSource) => Promise<Array<{ rawValue: string }>> };
type DetectorCtor = new (options: { formats: string[] }) => Detector;

const FRAME_MS = 200;

async function makeDecoder(): Promise<(video: HTMLVideoElement) => Promise<string | null>> {
  const Native = (window as unknown as { BarcodeDetector?: DetectorCtor & { getSupportedFormats?: () => Promise<string[]> } }).BarcodeDetector;
  if (Native) {
    try {
      const formats = (await Native.getSupportedFormats?.()) ?? ["qr_code"];
      if (formats.includes("qr_code")) {
        const detector = new Native({ formats: ["qr_code"] });
        return async (video) => (await detector.detect(video))[0]?.rawValue ?? null;
      }
    } catch {
      // Fall through to the JS decoder.
    }
  }
  const { default: jsQR } = await import("jsqr");
  const canvas = document.createElement("canvas");
  const context = canvas.getContext("2d", { willReadFrequently: true });
  return async (video) => {
    if (!context || video.videoWidth === 0) return null;
    // Decode a scaled-down frame: a QR held up to the desk fills most of it.
    const scale = Math.min(1, 640 / video.videoWidth);
    canvas.width = Math.round(video.videoWidth * scale);
    canvas.height = Math.round(video.videoHeight * scale);
    context.drawImage(video, 0, 0, canvas.width, canvas.height);
    const image = context.getImageData(0, 0, canvas.width, canvas.height);
    return jsQR(image.data, image.width, image.height, { inversionAttempts: "dontInvert" })?.data ?? null;
  };
}

export const cameraSource: ScannerSource = {
  async start(video, onCode) {
    if (!navigator.mediaDevices?.getUserMedia) throw new CameraError("unsupported");
    let stream: MediaStream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: "environment" } }, audio: false });
    } catch (error) {
      const name = (error as { name?: string }).name;
      if (name === "NotAllowedError" || name === "SecurityError") throw new CameraError("denied");
      if (name === "NotFoundError" || name === "OverconstrainedError") throw new CameraError("missing");
      throw new CameraError("failed");
    }

    video.srcObject = stream;
    video.setAttribute("playsinline", "true");
    video.muted = true;
    await video.play().catch(() => undefined);

    const decode = await makeDecoder();
    let stopped = false;
    let timer: number | undefined;
    const tick = async () => {
      if (stopped) return;
      try {
        const text = await decode(video);
        if (text && !stopped) onCode(text);
      } catch {
        // A frame that can't be read; try the next one.
      }
      if (!stopped) timer = window.setTimeout(() => void tick(), FRAME_MS);
    };
    void tick();

    return () => {
      stopped = true;
      window.clearTimeout(timer);
      stream.getTracks().forEach((track) => track.stop());
      video.srcObject = null;
    };
  },
};

/** The source in use: a test's, or the camera. */
export function scannerSource(): ScannerSource {
  const injected = (window as unknown as { __milosScannerSource?: ScannerSource }).__milosScannerSource;
  return injected ?? cameraSource;
}
