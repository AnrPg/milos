import { fireEvent, render, screen } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { useState } from "react";
import { describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";
import type { PointAnswer } from "@/components/spaces/cleaning-points";

import { CleaningPointsCarousel } from "./CleaningPointsCarousel";

vi.mock("@/i18n/ui", () => ({ useUiTranslations: () => (key: string) => key }));

const points = [
  { id: "p1", instruction: "Drains", url: "https://img/1.jpg" },
  { id: "p2", instruction: "Mirrors", url: "https://img/2.jpg" },
];

function Harness({ onAnswers }: { onAnswers: (answers: Record<string, PointAnswer>) => void }) {
  const [answers, setAnswers] = useState<Record<string, PointAnswer>>({});
  return (
    <CleaningPointsCarousel
      token="token"
      points={points}
      answers={answers}
      onChange={(id, answer) => {
        const next = { ...answers, [id]: answer };
        setAnswers(next);
        onAnswers(next);
      }}
    />
  );
}

function renderCarousel(onAnswers = vi.fn()) {
  render(
    <QueryClientProvider client={new QueryClient()}>
      <NextIntlClientProvider locale="en" messages={en} timeZone="UTC">
        <Harness onAnswers={onAnswers} />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
  return onAnswers;
}

describe("CleaningPointsCarousel", () => {
  it("«Clean» answers the point and moves to the next one", () => {
    const onAnswers = renderCarousel();
    expect(screen.getByTestId("cleaning-carousel-instruction")).toHaveTextContent("Drains");
    expect(screen.getByText("1 / 2")).toBeInTheDocument();

    fireEvent.click(screen.getByTestId("cleaning-point-cleaned"));

    expect(onAnswers).toHaveBeenLastCalledWith({ p1: { status: "cleaned" } });
    expect(screen.getByTestId("cleaning-carousel-instruction")).toHaveTextContent("Mirrors");
  });

  it("«Not cleaned» asks why, and the note is required", () => {
    const onAnswers = renderCarousel();
    fireEvent.click(screen.getByTestId("cleaning-point-not-cleaned"));

    expect(screen.getByText("Say why it was not cleaned.")).toBeInTheDocument();
    fireEvent.change(screen.getByTestId("cleaning-point-note"), { target: { value: "Out of spray" } });

    expect(onAnswers).toHaveBeenLastCalledWith({ p1: { status: "not_cleaned", note: "Out of spray" } });
    expect(screen.queryByText("Say why it was not cleaned.")).not.toBeInTheDocument();
    // Staying on the point, with an optional photo after.
    expect(screen.getByTestId("cleaning-carousel-instruction")).toHaveTextContent("Drains");
    expect(screen.getByText(/Photo after/)).toBeInTheDocument();
  });
});
