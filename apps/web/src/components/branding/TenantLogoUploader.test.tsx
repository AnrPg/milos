import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import type { OrganizationLogoApi } from "@/api/organization-branding";
import { TenantLogoUploader } from "@/components/branding/TenantLogoUploader";

vi.mock("@/i18n/ui", () => ({
  useUiTranslations: () => (key: string) => key,
}));

vi.mock("@/i18n/presentation", () => ({
  localizeError: (error: Error) => error.message,
}));

const uploadedBranding = {
  organization_id: "org-1",
  brand_name: "Gym",
  brand_logo_url: "https://media.test/organizations/org-1/branding/logo/new.png",
  brand_logo_uploaded: true,
  brand_primary_color: null,
};

function makeApi(): OrganizationLogoApi & { [K in keyof OrganizationLogoApi]: ReturnType<typeof vi.fn> } {
  return {
    requestUpload: vi.fn().mockResolvedValue({
      upload_url: "https://media.test/upload",
      key: "organizations/org-1/branding/logo/new.png",
      required_headers: { "content-type": "image/png" },
      expires_in: 900,
      max_bytes: 2 * 1024 * 1024,
    }),
    finalize: vi.fn().mockResolvedValue(uploadedBranding),
    remove: vi.fn().mockResolvedValue({ ...uploadedBranding, brand_logo_url: null, brand_logo_uploaded: false }),
  };
}

function fileInput() {
  return screen.getByLabelText("brandLogoChoose", { selector: "input" }) as HTMLInputElement;
}

describe("TenantLogoUploader", () => {
  beforeEach(() => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true }));
    URL.createObjectURL = vi.fn(() => "blob:preview");
    URL.revokeObjectURL = vi.fn();
  });

  it("previews a valid file, uploads it and reports the new branding", async () => {
    const api = makeApi();
    const onChange = vi.fn();
    render(<TenantLogoUploader api={api} currentUrl={null} uploaded={false} onChange={onChange} />);

    expect(screen.getByText("brandLogoNone")).toBeInTheDocument();

    const file = new File([new Uint8Array(64)], "logo.png", { type: "image/png" });
    fireEvent.change(fileInput(), { target: { files: [file] } });

    expect(await screen.findByAltText("brandLogoPreviewAlt")).toHaveAttribute("src", "blob:preview");

    fireEvent.click(screen.getByRole("button", { name: "brandLogoUpload" }));

    await waitFor(() => expect(onChange).toHaveBeenCalledWith(uploadedBranding));
    expect(api.finalize).toHaveBeenCalledWith("organizations/org-1/branding/logo/new.png");
    expect(screen.getByText("brandLogoSaved")).toBeInTheDocument();
  });

  it("rejects SVG and oversized files before contacting the API", () => {
    const api = makeApi();
    render(<TenantLogoUploader api={api} currentUrl={null} uploaded={false} onChange={vi.fn()} />);

    fireEvent.change(fileInput(), {
      target: { files: [new File(["<svg/>"], "logo.svg", { type: "image/svg+xml" })] },
    });
    expect(screen.getByRole("alert")).toHaveTextContent("brandLogoUnsupportedType");

    fireEvent.change(fileInput(), {
      target: { files: [new File([new Uint8Array(2 * 1024 * 1024 + 1)], "big.png", { type: "image/png" })] },
    });
    expect(screen.getByRole("alert")).toHaveTextContent("brandLogoTooLarge");

    expect(screen.queryByRole("button", { name: "brandLogoUpload" })).toBeNull();
    expect(api.requestUpload).not.toHaveBeenCalled();
  });

  it("offers replace and remove for an existing logo", async () => {
    const api = makeApi();
    const onChange = vi.fn();
    render(
      <TenantLogoUploader
        api={api}
        currentUrl="https://media.test/organizations/org-1/branding/logo/old.png"
        uploaded
        onChange={onChange}
      />,
    );

    expect(screen.getByAltText("brandLogoCurrentAlt")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "brandLogoReplace" })).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "brandLogoRemove" }));

    await waitFor(() => expect(api.remove).toHaveBeenCalled());
    expect(onChange).toHaveBeenCalledWith(expect.objectContaining({ brand_logo_url: null }));
    expect(await screen.findByText("brandLogoRemoved")).toBeInTheDocument();
  });

  it("explains that an external URL logo will be replaced", () => {
    render(
      <TenantLogoUploader api={makeApi()} currentUrl="https://cdn.example/logo.png" uploaded={false} onChange={vi.fn()} />,
    );

    expect(screen.getByText("brandLogoExternalUrl")).toBeInTheDocument();
  });

  it("shows the API error when finalization fails", async () => {
    const api = makeApi();
    api.finalize.mockRejectedValue(new Error("apiErrorUnsupportedBrandLogoType"));
    render(<TenantLogoUploader api={api} currentUrl={null} uploaded={false} onChange={vi.fn()} />);

    fireEvent.change(fileInput(), {
      target: { files: [new File([new Uint8Array(8)], "logo.png", { type: "image/png" })] },
    });
    fireEvent.click(screen.getByRole("button", { name: "brandLogoUpload" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("apiErrorUnsupportedBrandLogoType");
  });
});
