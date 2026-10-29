import { render } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { FolderIcon, WorkoutFileIcon } from "./LibraryIcons";

describe("vault icons", () => {
  it("draws a folder with its emoji and item count in the middle", () => {
    const { container } = render(<FolderIcon mark={{ kind: "emoji", emoji: "👥" }} count={4} />);
    const icon = container.querySelector('[data-icon="folder"]');
    expect(icon).not.toBeNull();
    expect(icon?.textContent).toBe("👥4");
  });

  it("draws the member glyph instead of an emoji for Variations for member", () => {
    const { container } = render(<FolderIcon mark={{ kind: "transfer" }} />);
    // Folder shape plus the person-to-person glyph, and no stray emoji text.
    expect(container.querySelectorAll("svg")).toHaveLength(2);
    expect(container.textContent).toBe("");
  });

  it("shows the date on date folders in tiles and leaves it out in the list", () => {
    const mark = { kind: "date", main: "12", caption: "Οκτ" } as const;
    expect(render(<FolderIcon mark={mark} />).container.textContent).toBe("Οκτ12");
    expect(render(<FolderIcon mark={mark} size="inline" />).container.textContent).toBe("");
  });

  it("draws a page with the workout emoji and a draft dot", () => {
    const { container } = render(<WorkoutFileIcon emoji="🦵" draft />);
    const icon = container.querySelector('[data-icon="file"]');
    expect(icon?.textContent).toBe("🦵");
    expect(icon?.querySelectorAll("span")).toHaveLength(2);
  });

  it("colours only through theme variables", () => {
    const { container } = render(
      <>
        <FolderIcon mark={{ kind: "transfer" }} />
        <WorkoutFileIcon emoji="🔥" />
      </>,
    );
    const colours = [...container.querySelectorAll("path, circle")].flatMap((node) => [node.getAttribute("fill"), node.getAttribute("stroke")]);
    for (const colour of colours.filter((value): value is string => !!value && value !== "none")) {
      expect(colour).toMatch(/var\(--/);
    }
  });
});
