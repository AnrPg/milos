import { describe, expect, test } from "vitest";

import { configuredMediaOrigins } from "@/proxy";

describe("configuredMediaOrigins", () => {
  test("uses the explicit public media origin allowlist first", () => {
    expect(
      configuredMediaOrigins({
        NEXT_PUBLIC_MEDIA_ORIGIN: "https://s3-milos.4kq.net, http://media.localhost:18080",
        MINIO_PUBLIC_ENDPOINT: "https://ignored.example.net",
      })
    ).toBe("https://s3-milos.4kq.net http://media.localhost:18080");
  });

  test("falls back to the MinIO public endpoint for presigned uploads", () => {
    expect(
      configuredMediaOrigins({
        MINIO_PUBLIC_ENDPOINT: "https://s3-milos.4kq.net",
      })
    ).toBe("https://s3-milos.4kq.net");
  });
});
