import { describe, expect, it } from "vitest";

import type { OnDemandVideo } from "@/api/content";
import { filterVideosByTag, safeVideoUrl, videoHost, videoTags } from "@/components/client/video";

function video(id: string, tags: string[]): OnDemandVideo {
  return {
    id,
    title: id,
    tags,
    video_url: "https://www.youtube.com/watch?v=abc",
    archived_at: null,
    published_at: "2026-10-01T00:00:00Z",
  };
}

describe("on-demand video helpers", () => {
  it("only opens https links", () => {
    expect(safeVideoUrl("https://vimeo.com/123")).toBe("https://vimeo.com/123");
    expect(safeVideoUrl("http://vimeo.com/123")).toBeNull();
    expect(safeVideoUrl("javascript:alert(1)")).toBeNull();
    expect(safeVideoUrl("not a url")).toBeNull();
    expect(safeVideoUrl(null)).toBeNull();
  });

  it("names the host", () => {
    expect(videoHost("https://www.youtube.com/watch?v=abc")).toBe("youtube.com");
    expect(videoHost("https://youtu.be/abc")).toBe("youtube.com");
    expect(videoHost("https://cdn.example.org/v.mp4")).toBe("cdn.example.org");
    expect(videoHost("ftp://x")).toBeNull();
  });

  it("collects tags once and filters by tag ignoring case", () => {
    const videos = [video("a", ["Mobility", "core"]), video("b", ["mobility "]), video("c", [])];
    expect(videoTags(videos, "en")).toEqual(["core", "Mobility"]);
    expect(filterVideosByTag(videos, ["MOBILITY"]).map((v) => v.id)).toEqual(["a", "b"]);
    expect(filterVideosByTag(videos, [])).toHaveLength(3);
  });
});
