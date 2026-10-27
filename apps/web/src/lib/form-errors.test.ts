import { describe, expect, it, vi } from "vitest";

import { ApiError } from "@/api/client";
import { explainFieldMessage, formErrorsFrom, invalidFieldProps, stillApplies } from "@/lib/form-errors";

const translate = vi.fn((key: string, params?: Record<string, unknown>) =>
  params ? `${key}:${JSON.stringify(params)}` : key,
);

const validation = (errors: Record<string, unknown>) =>
  new ApiError(422, "scheduled_at: must be in the future", { code: "validation_failed", errors });

describe("explainFieldMessage", () => {
  it("turns the API's rule wording into a plain sentence with its numbers", () => {
    expect(explainFieldMessage("can't be blank", translate)).toBe("formErrRequired");
    expect(explainFieldMessage("must be in the future", translate)).toBe("formErrMustBeFuture");
    expect(explainFieldMessage("must be greater than 0", translate)).toBe('formErrGreaterThan:{"number":"0"}');
    expect(explainFieldMessage("must be less than or equal to 1440", translate)).toBe('formErrAtMost:{"number":"1440"}');
    expect(explainFieldMessage("should be at most 120 character(s)", translate)).toBe('formErrTooLong:{"count":120}');
  });

  it("never shows the API's own wording for a rule it does not know", () => {
    expect(explainFieldMessage("violates check constraint xyz", translate)).toBe("formErrInvalid");
  });
});

describe("formErrorsFrom", () => {
  it("puts each reason on its field and says so in the form's notice", () => {
    const errors = formErrorsFrom(validation({ scheduled_at: ["must be in the future"] }), translate, ["name", "scheduled_at"]);
    expect(errors.fields).toEqual({ scheduled_at: "formErrMustBeFuture" });
    expect(errors.message).toBe("formErrFixHighlighted");
  });

  it("lets a form explain a field in its own words", () => {
    const errors = formErrorsFrom(validation({ scheduled_at: ["must be in the future"] }), translate, ["scheduled_at"], {
      overrides: { scheduled_at: () => "It is 23:33 at the box now." },
    });
    expect(errors.fields.scheduled_at).toBe("It is 23:33 at the box now.");
  });

  it("keeps the reason of a field the form does not show in the notice, never a false 'highlighted'", () => {
    const errors = formErrorsFrom(validation({ organization_id: ["can't be blank"] }), translate, ["name"]);
    expect(errors.fields).toEqual({});
    expect(errors.message).toBe("formErrRequired");
  });

  it("falls back to the localized error when the failure is not about fields", () => {
    const errors = formErrorsFrom(new ApiError(404, "Not found", {}), translate, ["name"]);
    expect(errors).toEqual({ fields: {}, message: "apiErrorNotFound" });
    expect(formErrorsFrom(new Error("boom"), translate, ["name"], { fallback: "Could not save" }).message).toBe("Could not save");
  });
});

describe("stillApplies", () => {
  it("drops a field's reason once its value differs from the one sent", () => {
    const errors = { fields: { name: "formErrRequired", capacity: "formErrGreaterThan" }, message: "formErrFixHighlighted" };
    expect(stillApplies(errors, { name: "", capacity: 0 }, { name: "WOD", capacity: 0 })).toEqual({ capacity: "formErrGreaterThan" });
    expect(stillApplies(null, null, {})).toEqual({});
  });
});

describe("invalidFieldProps", () => {
  it("marks a wrong field for assistive tech and links its reason", () => {
    expect(invalidFieldProps("Fill it in.", "err-name")).toEqual({ "aria-invalid": true, "aria-describedby": "err-name" });
    expect(invalidFieldProps(null, "err-name")).toEqual({});
  });
});
