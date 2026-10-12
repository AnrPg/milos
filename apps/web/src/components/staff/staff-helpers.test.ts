import { describe, expect, it } from "vitest";

import { ApiError } from "@/api/client";

import {
  activeBookings,
  appointmentRange,
  capacityOptions,
  centsToInput,
  chatThreadHref,
  corporatePackages,
  formatIsoDate,
  fromDateTimeLocal,
  groupSlotsByDay,
  isHttpsUrl,
  localDateKey,
  optionalInt,
  parseEuroToCents,
  parsePaymentTerms,
  parseTags,
  remainingBeneficiaryPlaces,
  replyUrgency,
  seatUsage,
  sharedSubscriptions,
  sortReplyQueue,
  staffErrorKey,
  staffErrorMessage,
  startOfWeek,
  toDateTimeLocal,
  videoState,
} from "./staff-helpers";

const translate = (key: string) => `t:${key}`;

describe("staff error messages", () => {
  it("maps Phase C codes to their own keys", () => {
    const error = new ApiError(409, "x", { code: "beneficiary_limit_reached" });
    expect(staffErrorKey(error)).toBe("stfErrBeneficiaryLimit");
    expect(staffErrorMessage(error, translate)).toBe("t:stfErrBeneficiaryLimit");
    expect(staffErrorMessage(new ApiError(409, "x", { code: "corporate_seats_full" }), translate)).toBe(
      "t:stfErrSeatsFull",
    );
    expect(staffErrorMessage(new ApiError(409, "x", { code: "form_review_closed" }), translate)).toBe(
      "t:stfErrFormReviewClosed",
    );
  });

  it("falls back to the shared API error copy", () => {
    expect(staffErrorKey(new Error("boom"))).toBeNull();
    expect(staffErrorMessage(new ApiError(404, "x", {}), translate)).toBe("t:apiErrorNotFound");
    expect(staffErrorMessage(new Error("boom"), translate)).toBe("t:apiErrorRequestFailed");
  });
});

describe("form helpers", () => {
  it("accepts only https links", () => {
    expect(isHttpsUrl("https://youtu.be/abc")).toBe(true);
    expect(isHttpsUrl("  https://vimeo.com/1 ")).toBe(true);
    expect(isHttpsUrl("http://example.com")).toBe(false);
    expect(isHttpsUrl("javascript:alert(1)")).toBe(false);
    expect(isHttpsUrl("not a url")).toBe(false);
  });

  it("parses comma separated tags without duplicates", () => {
    expect(parseTags(" mobility, Core ,core,, hips")).toEqual(["mobility", "Core", "hips"]);
    expect(parseTags("a,b,c", 2)).toEqual(["a", "b"]);
    expect(parseTags("")).toEqual([]);
  });

  it("reads optional integers", () => {
    expect(optionalInt("")).toBeNull();
    expect(optionalInt(" 2200 ")).toBe(2200);
    expect(optionalInt("12.5")).toBeNaN();
    expect(optionalInt("-3")).toBeNaN();
  });

  it("derives the video state", () => {
    expect(videoState({ published_at: null, archived_at: null })).toBe("draft");
    expect(videoState({ published_at: "2026-10-01T00:00:00Z", archived_at: null })).toBe("published");
    expect(videoState({ published_at: "2026-10-01T00:00:00Z", archived_at: "2026-10-02T00:00:00Z" })).toBe(
      "archived",
    );
  });
});

describe("reply queue", () => {
  const now = new Date("2026-10-12T10:00:00Z");

  it("classifies urgency", () => {
    expect(replyUrgency({ overdue: true, due_at: "2026-10-12T09:00:00Z" }, now)).toBe("overdue");
    expect(replyUrgency({ overdue: false, due_at: "2026-10-12T11:00:00Z" }, now)).toBe("due_soon");
    expect(replyUrgency({ overdue: false, due_at: "2026-10-13T11:00:00Z" }, now)).toBe("on_time");
    expect(replyUrgency({ overdue: false, due_at: null }, now)).toBe("on_time");
  });

  it("sorts overdue first, then by due time", () => {
    const items = [
      { id: "a", overdue: false, due_at: null, sent_at: "2026-10-12T01:00:00Z" },
      { id: "b", overdue: false, due_at: "2026-10-12T12:00:00Z", sent_at: "2026-10-12T02:00:00Z" },
      { id: "c", overdue: true, due_at: "2026-10-12T08:00:00Z", sent_at: "2026-10-11T02:00:00Z" },
      { id: "d", overdue: false, due_at: "2026-10-12T11:00:00Z", sent_at: "2026-10-12T03:00:00Z" },
    ];
    expect(sortReplyQueue(items).map((item) => item.id)).toEqual(["c", "d", "b", "a"]);
  });
});

describe("appointment calendar helpers", () => {
  it("starts weeks on Monday", () => {
    const sunday = new Date(2026, 9, 18, 15, 30);
    expect(localDateKey(startOfWeek(sunday))).toBe("2026-10-12");
    expect(localDateKey(startOfWeek(new Date(2026, 9, 12, 0, 0)))).toBe("2026-10-12");
  });

  it("builds week and day ranges", () => {
    const anchor = new Date(2026, 9, 14, 9, 0);
    const week = appointmentRange(anchor, "week");
    expect(localDateKey(week.from)).toBe("2026-10-12");
    expect(localDateKey(week.to)).toBe("2026-10-19");
    const day = appointmentRange(anchor, "day");
    expect(localDateKey(day.from)).toBe("2026-10-14");
    expect(localDateKey(day.to)).toBe("2026-10-15");
  });

  it("groups slots by local day in time order", () => {
    const late = new Date(2026, 9, 13, 18, 0).toISOString();
    const early = new Date(2026, 9, 13, 7, 0).toISOString();
    const other = new Date(2026, 9, 12, 9, 0).toISOString();
    const groups = groupSlotsByDay([
      { id: "late", starts_at: late },
      { id: "other", starts_at: other },
      { id: "early", starts_at: early },
    ]);
    expect(groups.map((group) => group.day)).toEqual(["2026-10-12", "2026-10-13"]);
    expect(groups[1].slots.map((slot) => slot.id)).toEqual(["early", "late"]);
  });

  it("ignores cancelled bookings in the roster count", () => {
    expect(activeBookings([{ status: "booked" }, { status: "cancelled" }, { status: "no_show" }])).toHaveLength(2);
    expect(activeBookings(undefined)).toEqual([]);
  });

  it("round-trips datetime-local values", () => {
    const date = new Date(2026, 9, 14, 7, 5);
    expect(toDateTimeLocal(date)).toBe("2026-10-14T07:05");
    expect(fromDateTimeLocal("2026-10-14T07:05")).toBe(date.toISOString());
    expect(fromDateTimeLocal("")).toBeNull();
    expect(fromDateTimeLocal("nope")).toBeNull();
  });

  it("limits capacity by format", () => {
    expect(capacityOptions("one_to_one")).toEqual([1]);
    expect(capacityOptions("semi_private")).toEqual([2, 3, 4]);
  });
});

describe("shared memberships", () => {
  it("counts the payer in the beneficiary limit", () => {
    expect(remainingBeneficiaryPlaces(3, 0)).toBe(2);
    expect(remainingBeneficiaryPlaces(3, 2)).toBe(0);
    expect(remainingBeneficiaryPlaces(2, 5)).toBe(0);
    expect(remainingBeneficiaryPlaces(undefined, 0)).toBeNull();
  });
});

describe("payment models", () => {
  it("keeps only active corporate packages", () => {
    const packages = [
      { id: "a", package_type: "corporate", active: true },
      { id: "b", package_type: "membership", active: true },
      { id: "c", package_type: "corporate", active: false },
      { id: "d", package_type: "corporate" },
    ];
    expect(corporatePackages(packages).map((pkg) => pkg.id)).toEqual(["a", "d"]);
  });

  it("formats seat usage", () => {
    expect(seatUsage(3, 10)).toBe("3 / 10");
    expect(seatUsage(3, null)).toBe("3");
  });

  it("finds active shared subscriptions", () => {
    const subscriptions = [
      { id: "a", package_type: "shared", status: "active" },
      { id: "b", package_type: "shared", status: "cancelled" },
      { id: "c", package_type: "membership", status: "active" },
    ];
    expect(sharedSubscriptions(subscriptions).map((subscription) => subscription.id)).toEqual(["a"]);
  });

  it("links reply queue items to the chat thread", () => {
    expect(chatThreadHref("t 1")).toBe("/account/activity/chats?thread=t%201");
  });
});

describe("corporate invoice inputs", () => {
  it("parses euro amounts", () => {
    expect(parseEuroToCents("12,50")).toBe(1250);
    expect(parseEuroToCents(" 200 ")).toBe(20000);
    expect(parseEuroToCents("0")).toBeNull();
    expect(parseEuroToCents("1.234")).toBeNull();
    expect(parseEuroToCents("abc")).toBeNull();
    expect(centsToInput(15000)).toBe("150.00");
  });

  it("parses payment terms", () => {
    expect(parsePaymentTerms("14")).toBe(14);
    expect(parsePaymentTerms("0")).toBe(0);
    expect(parsePaymentTerms("121")).toBeNull();
    expect(parsePaymentTerms("")).toBeNull();
  });

  it("maps invoicing errors", () => {
    expect(staffErrorKey(new ApiError(409, "x", { code: "corporate_invoice_has_payments" }))).toBe(
      "stfErrInvoiceHasPayments",
    );
    expect(staffErrorKey(new ApiError(422, "x", { code: "corporate_billing_email_missing" }))).toBe(
      "stfErrBillingEmailMissing",
    );
  });
});

describe("formatIsoDate", () => {
  it("keeps the calendar day", () => {
    expect(formatIsoDate("en-GB", "2026-10-01")).toBe("1 Oct 2026");
    expect(formatIsoDate("en-GB", null)).toBe("—");
  });
});
