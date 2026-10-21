/**
 * The presigned PUT shared by every browser upload (ADR-148 box photos,
 * ADR-157 post media): the body goes straight to storage with the headers
 * the API signed, reporting progress and stopping when `signal` aborts.
 * XHR rather than fetch, because only XHR reports upload progress everywhere.
 */
export class PresignedUploadError extends Error {
  constructor(
    public readonly reason: "network" | "aborted" | "rejected",
    public readonly status?: number,
  ) {
    super(reason);
    this.name = "PresignedUploadError";
  }
}

export function putPresigned(
  url: string,
  body: Blob,
  headers: Record<string, string> = {},
  options: { onProgress?: (loaded: number, total: number) => void; signal?: AbortSignal } = {},
): Promise<void> {
  const { onProgress, signal } = options;
  return new Promise((resolve, reject) => {
    if (signal?.aborted) {
      reject(new PresignedUploadError("aborted"));
      return;
    }
    const xhr = new XMLHttpRequest();
    const abort = () => xhr.abort();
    const done = () => signal?.removeEventListener("abort", abort);
    xhr.open("PUT", url);
    for (const [name, value] of Object.entries(headers)) xhr.setRequestHeader(name, value);
    xhr.upload.onprogress = (event) => {
      if (event.lengthComputable) onProgress?.(event.loaded, event.total);
    };
    xhr.onload = () => {
      done();
      if (xhr.status >= 200 && xhr.status < 300) {
        onProgress?.(body.size, body.size);
        resolve();
      } else {
        reject(new PresignedUploadError("rejected", xhr.status));
      }
    };
    xhr.onerror = () => {
      done();
      reject(new PresignedUploadError("network"));
    };
    xhr.onabort = () => {
      done();
      reject(new PresignedUploadError("aborted"));
    };
    signal?.addEventListener("abort", abort, { once: true });
    xhr.send(body);
  });
}
