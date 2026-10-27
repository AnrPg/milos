import { afterEach, describe, expect, it, vi } from "vitest";

import { DEVICE_ID_HEADER, DEVICE_ID_KEY, deviceHeaders, deviceId } from "./device-id";

describe("device id", () => {
  afterEach(() => {
    window.localStorage.clear();
    vi.restoreAllMocks();
  });

  it("creates a url-safe id once and keeps it", () => {
    const first = deviceId();
    expect(first).toMatch(/^[A-Za-z0-9_-]{32}$/);
    expect(window.localStorage.getItem(DEVICE_ID_KEY)).toBe(first);
    expect(deviceId()).toBe(first);
  });

  it("replaces a stored value that is not an id", () => {
    window.localStorage.setItem(DEVICE_ID_KEY, "not an id!");
    const id = deviceId();
    expect(id).not.toBe("not an id!");
    expect(id).toMatch(/^[A-Za-z0-9_-]{16,128}$/);
  });

  it("sends the id as the sign-in header", () => {
    const id = deviceId();
    expect(deviceHeaders()).toEqual({ [DEVICE_ID_HEADER]: id });
  });

  it("sends nothing when storage is blocked", () => {
    vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
      throw new Error("blocked");
    });
    expect(deviceId()).toBeNull();
    expect(deviceHeaders()).toEqual({});
  });
});
