import fs from "node:fs";
import path from "node:path";

import { render, screen, waitFor } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { afterEach, describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";
import { FITNESS_QUALITIES } from "@/lib/anatomy/qualities";
import { MUSCLE_NODES } from "@/lib/anatomy/taxonomy";

import { AnatomyFigure } from "./AnatomyFigure";
import { AnatomyThumb } from "./AnatomyThumb";

const createFigure = vi.fn();
const renderThumb = vi.fn();

vi.mock("@/lib/anatomy/renderer/figure-controller", () => ({ createFigure: (...args: unknown[]) => createFigure(...args) }));
vi.mock("@/lib/anatomy/renderer/thumbs", () => ({ renderThumb: (...args: unknown[]) => renderThumb(...args) }));

function wrap(ui: React.ReactNode) {
  return render(
    <NextIntlClientProvider locale="en" messages={en}>
      {ui}
    </NextIntlClientProvider>,
  );
}

afterEach(() => {
  createFigure.mockReset();
  renderThumb.mockReset();
});

describe("AnatomyFigure", () => {
  it("describes the highlighted muscles by role and mounts the lazy renderer", async () => {
    const controller = { update: vi.fn(), dispose: vi.fn() };
    createFigure.mockResolvedValue(controller);
    const { unmount } = wrap(
      <AnatomyFigure highlights={{ quadriceps: "primary", glutes: "primary", hamstrings: "secondary", "gluteus-medius": "felt" }} view="both" interactive />,
    );

    const figure = screen.getByRole("img", {
      name: "Body figure. Primary: Glutes and Quadriceps. Secondary: Hamstrings. Felt: Gluteus medius.",
    });
    expect(figure).toHaveAttribute("aria-roledescription", "interactive body figure");
    await waitFor(() => expect(figure).toHaveAttribute("data-anatomy-status", "ready"));
    expect(createFigure).toHaveBeenCalledWith(figure, expect.objectContaining({ view: "both", interactive: true, onPick: null }));

    unmount();
    expect(controller.dispose).toHaveBeenCalled();
  });

  it("forwards picks as (nodeId, level)", async () => {
    let options: { onPick: ((pick: { nodeId: string; level: string }) => void) | null } | undefined;
    createFigure.mockImplementation(async (_container: HTMLElement, given: typeof options) => {
      options = given;
      return { update: vi.fn(), dispose: vi.fn() };
    });
    const onPick = vi.fn();
    wrap(<AnatomyFigure highlights={{}} onPick={onPick} />);
    await waitFor(() => expect(options).toBeDefined());
    options!.onPick!({ nodeId: "deltoid", level: "group" });
    expect(onPick).toHaveBeenCalledWith("deltoid", "group");
  });

  it("falls back to text when WebGL fails", async () => {
    createFigure.mockRejectedValue(new Error("no webgl"));
    wrap(<AnatomyFigure highlights={{}} />);
    expect(await screen.findByText(en.Anatomy.figure.unavailable)).toBeInTheDocument();
    expect(screen.getByRole("img", { name: "Body figure. No muscles highlighted." })).toBeInTheDocument();
  });

  it("renders a static thumb through the shared thumbnail renderer", async () => {
    renderThumb.mockResolvedValue("data:image/png;base64,AAAA");
    const { container } = wrap(<AnatomyFigure highlights={{ deltoid: "primary" }} size="thumb" />);
    await waitFor(() => expect(container.querySelector("img")).toHaveAttribute("src", "data:image/png;base64,AAAA"));
    expect(createFigure).not.toHaveBeenCalled();
    expect(renderThumb).toHaveBeenCalledWith(expect.objectContaining({ width: 32, height: 64, view: "front" }));
  });
});

describe("AnatomyThumb", () => {
  it("labels the image and asks the shared renderer for it", async () => {
    renderThumb.mockResolvedValue("data:image/png;base64,BBBB");
    wrap(<AnatomyThumb highlights={{ "latissimus-dorsi": "secondary" }} view="both" />);
    expect(screen.getByRole("img", { name: "Body figure. Secondary: Latissimus dorsi." })).toBeInTheDocument();
    await waitFor(() => expect(renderThumb).toHaveBeenCalledWith(expect.objectContaining({ width: 64, height: 64, view: "both" })));
  });
});

describe("Anatomy messages", () => {
  const locales = ["ar", "bg", "de", "el", "en", "es", "fr", "he", "it", "nl", "pt-PT", "ru"];

  it.each(locales)("%s names every taxonomy node, quality and role", (locale) => {
    const messages = JSON.parse(fs.readFileSync(path.resolve(__dirname, `../../../messages/${locale}.json`), "utf8"));
    const anatomy = messages.Anatomy;
    for (const node of MUSCLE_NODES) expect(anatomy.muscle[node.id], node.id).toBeTruthy();
    for (const quality of FITNESS_QUALITIES) expect(anatomy.quality[quality], quality).toBeTruthy();
    for (const role of ["primary", "secondary", "stabilizer", "felt"]) expect(anatomy.role[role]).toBeTruthy();
  });
});
