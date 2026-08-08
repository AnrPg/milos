import { describe, expect, it } from "vitest";

import { sanitizeWorkoutDslPaste } from "@/lib/workout-dsl-editor-data";

describe("sanitizeWorkoutDslPaste", () => {
  it("removes executable and embedded content while retaining ordinary text", () => {
    const sanitized = sanitizeWorkoutDslPaste(
      '<p onclick="steal()">[workout]</p><script>alert(1)</script><iframe src="https://evil.test"></iframe>',
    );

    expect(sanitized).toContain("[workout]");
    expect(sanitized).not.toContain("onclick");
    expect(sanitized).not.toContain("script");
    expect(sanitized).not.toContain("iframe");
  });

  it("removes dangerous URLs and inline styles but keeps https and mailto links", () => {
    const sanitized = sanitizeWorkoutDslPaste(
      '<a href="javascript:alert(1)" style="color:red">bad</a><a href="https://example.test">safe</a><a href="mailto:coach@example.test">mail</a>',
    );

    expect(sanitized).not.toContain("javascript:");
    expect(sanitized).not.toContain("style=");
    expect(sanitized).toContain('href="https://example.test"');
    expect(sanitized).toContain('href="mailto:coach@example.test"');
  });

  it("removes protocol-relative URLs from rich editor paste content", () => {
    const sanitized = sanitizeWorkoutDslPaste(
      '<a href="//evil.example/phish">bad</a><img src="//evil.example/pixel.png"><a href="/workouts/1">local</a>',
    );

    expect(sanitized).not.toContain("//evil.example");
    expect(sanitized).toContain('href="/workouts/1"');
  });
});
