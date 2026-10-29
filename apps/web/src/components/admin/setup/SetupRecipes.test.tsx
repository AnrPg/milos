import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../../messages/en.json";
import { ApiError } from "@/api/client";

import { applied, ownedPlan, plan, recipesPayload } from "./fixtures";
import { SetupRecipeCard } from "./SetupRecipeCard";
import { SetupRecipes } from "./SetupRecipes";

const api = vi.hoisted(() => ({
  fetchSetupRecipes: vi.fn(),
  previewSetupRecipe: vi.fn(),
  applySetupRecipe: vi.fn(),
  fetchSettingsCatalog: vi.fn(),
}));

vi.mock("@/api/setup", () => api);
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "token" } }) }));
vi.mock("@/lib/organization-slug", () => ({ useOrganizationSlug: () => "kypseli", adminHref: (href: string) => href }));
vi.mock("@/i18n/ui", () => ({ useUiTranslations: () => (key: string) => key }));
vi.mock("@/i18n/use-ui-locale", () => ({ useUiLocale: () => "en" }));

function renderWith(node: React.ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <NextIntlClientProvider locale="en" messages={en}>
      <QueryClientProvider client={client}>{node}</QueryClientProvider>
    </NextIntlClientProvider>,
  );
}

beforeEach(() => {
  Object.values(api).forEach((fn) => fn.mockReset());
  api.fetchSetupRecipes.mockResolvedValue(recipesPayload());
  api.previewSetupRecipe.mockResolvedValue(plan);
  api.applySetupRecipe.mockResolvedValue(applied);
});

async function openPreview() {
  renderWith(<SetupRecipes />);
  expect(await screen.findByRole("heading", { name: "What kind of box do you run?" })).toBeInTheDocument();
  const continueButton = screen.getByRole("button", { name: "Continue" });
  expect(continueButton).toBeDisabled();
  fireEvent.click(screen.getByTestId("recipe-crossfit_box"));
  fireEvent.click(continueButton);
  await screen.findByRole("heading", { name: "CrossFit box: what will be set up" });
  await screen.findByTestId("recipe-apply");
}

describe("SetupRecipes (s10 A)", () => {
  it("previews the packages, class types and rules, and applies with the changed price", async () => {
    await openPreview();
    expect(screen.getByLabelText("Unlimited")).toHaveValue("75");
    expect(screen.getByText("Open gym")).toBeInTheDocument();
    expect(screen.getByText("Bookings confirmed automatically")).toBeInTheDocument();
    expect(screen.getByText("Bookings open 7 days ahead")).toBeInTheDocument();
    expect(screen.getByText("Late cancellation: 2 hours")).toBeInTheDocument();
    expect(screen.getByText(/Plus 1 setting with a good default/)).toBeInTheDocument();

    fireEvent.change(screen.getByLabelText("Unlimited"), { target: { value: "80" } });
    fireEvent.click(screen.getByTestId("recipe-apply"));

    await waitFor(() => expect(api.applySetupRecipe).toHaveBeenCalledWith("token", "crossfit_box", { setup_unlimited: 8000 }, "all"));
    expect(await screen.findByTestId("recipe-applied")).toHaveTextContent("Your box is set up as CrossFit box");
    expect(screen.getByTestId("recipe-applied")).toHaveTextContent("2 subscription packages · 2 class types · 4 rules");
    expect(screen.getByRole("link", { name: /Bring your members/ })).toHaveAttribute("href", "/admin/users/import");
  });

  it("asks what happens to the settings the owner already changed (2026-10-29)", async () => {
    api.previewSetupRecipe.mockResolvedValue(ownedPlan);
    api.applySetupRecipe.mockResolvedValue({ ...applied, plan: { ...applied.plan, kept: ["scheduling.default_capacity"] } });
    await openPreview();

    const owned = screen.getByTestId("recipe-owner-values");
    expect(owned).toHaveTextContent("1 setting you already changed");
    const row = screen.getByTestId("owner-value-scheduling.default_capacity");
    expect(row).toHaveTextContent("Places per class");
    expect(row).toHaveTextContent("20");
    expect(row).toHaveTextContent("16");

    fireEvent.click(screen.getByTestId("recipe-apply"));
    expect(await screen.findByText("Choose what happens to the settings you changed.")).toBeInTheDocument();
    expect(api.applySetupRecipe).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole("radio", { name: /Keep mine/ }));
    fireEvent.click(screen.getByTestId("recipe-apply"));
    await waitFor(() => expect(api.applySetupRecipe).toHaveBeenCalledWith("token", "crossfit_box", {}, "defaults_only"));
    expect(await screen.findByTestId("recipe-kept")).toHaveTextContent("1 setting kept as you set it");
  });

  it("keeps a wrong price in the form and sends nothing", async () => {
    await openPreview();
    fireEvent.change(screen.getByLabelText("Unlimited"), { target: { value: "lots" } });
    fireEvent.click(screen.getByTestId("recipe-apply"));
    expect(await screen.findByText("Enter an amount, e.g. 75 or 75.50.")).toBeInTheDocument();
    expect(screen.getByLabelText("Unlimited")).toHaveAttribute("aria-invalid", "true");
    expect(api.applySetupRecipe).not.toHaveBeenCalled();
  });

  it("shows the API's refusal inside the screen", async () => {
    api.applySetupRecipe.mockRejectedValue(new ApiError(422, "x", { code: "invalid_recipe_prices" } as never));
    await openPreview();
    fireEvent.click(screen.getByTestId("recipe-apply"));
    expect(await screen.findByText("A price is not valid. Enter an amount, e.g. 75 or 75.50.")).toBeInTheDocument();
  });

  it("lets only the owner apply", async () => {
    api.fetchSetupRecipes.mockResolvedValue(recipesPayload({ can_apply: false }));
    await openPreview();
    expect(screen.getByText("Only the owner applies a recipe.")).toBeInTheDocument();
    expect(screen.getByTestId("recipe-apply")).toBeDisabled();
  });

  it("goes back to the kinds of box", async () => {
    await openPreview();
    fireEvent.click(screen.getByRole("button", { name: /Kind of box/ }));
    expect(await screen.findByRole("heading", { name: "What kind of box do you run?" })).toBeInTheDocument();
  });
});

describe("SetupRecipeCard", () => {
  it("invites an owner whose box has no recipe yet", async () => {
    renderWith(<SetupRecipeCard membership={{ role: "owner" }} />);
    expect(await screen.findByTestId("setup-recipe-card")).toHaveTextContent("What kind of box do you run?");
    expect(screen.getByRole("link", { name: "Start" })).toHaveAttribute("href", "/admin/setup");
  });

  it("stays away once a recipe is applied, and for staff who are not the owner", async () => {
    api.fetchSetupRecipes.mockResolvedValue(recipesPayload({ applications: [applied.application] as never }));
    const { unmount } = renderWith(<SetupRecipeCard membership={{ role: "owner" }} />);
    await waitFor(() => expect(api.fetchSetupRecipes).toHaveBeenCalled());
    expect(screen.queryByTestId("setup-recipe-card")).not.toBeInTheDocument();
    unmount();

    api.fetchSetupRecipes.mockClear();
    renderWith(<SetupRecipeCard membership={{ role: "admin" }} />);
    expect(screen.queryByTestId("setup-recipe-card")).not.toBeInTheDocument();
    expect(api.fetchSetupRecipes).not.toHaveBeenCalled();
  });
});
