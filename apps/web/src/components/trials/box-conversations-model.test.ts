import { describe, expect, it } from "vitest";

import type { Provider } from "@/api/providers";
import type { BoxConversationSummary } from "@/api/trials";

import { boxesToWrite } from "./box-conversations-model";

const provider = (organization_id: string, kind: string, slug: string | null) =>
  ({ organization_id, kind, slug, name: `Box ${organization_id}` }) as unknown as Provider;
const conversation = (organization_id: string) =>
  ({ box: { organization_id, slug: organization_id, name: organization_id } }) as unknown as BoxConversationSummary;

describe("boxesToWrite (ADR-282)", () => {
  it("offers each of your boxes you have not written to yet", () => {
    const providers = [provider("a", "gym", "a"), provider("b", "gym", "b"), provider("c", "coach", "c"), provider("d", "gym", null)];
    expect(boxesToWrite(providers, [conversation("a")])).toEqual([{ slug: "b", name: "Box b" }]);
  });

  it("offers nothing without boxes", () => {
    expect(boxesToWrite([], [])).toEqual([]);
  });
});
