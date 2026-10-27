import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { DraftConflictError, DraftSaver, type DraftSaveStatus } from "./draft-saver";

type Payload = { title: string };

class StaleRevision extends Error {}

/** A stand-in for the API: refuses saves based on an old revision, like the server. */
function fakeServer({ latencyMs = 0 } = {}) {
  const state = { revision: 3, inFlight: 0, maxInFlight: 0, saves: [] as Array<Payload & { expected_source_revision: number }> };
  const send = async (payload: Payload & { expected_source_revision: number }) => {
    state.inFlight += 1;
    state.maxInFlight = Math.max(state.maxInFlight, state.inFlight);
    try {
      if (latencyMs) await new Promise((resolve) => setTimeout(resolve, latencyMs));
      if (payload.expected_source_revision !== state.revision) throw new StaleRevision();
      state.revision += 1;
      state.saves.push(payload);
      return { dsl_source_revision: state.revision };
    } finally {
      state.inFlight -= 1;
    }
  };
  return { state, send };
}

function makeSaver(server: ReturnType<typeof fakeServer>) {
  const statuses: DraftSaveStatus[] = [];
  const saved: number[] = [];
  const saver = new DraftSaver<Payload>({
    isConflict: (error) => error instanceof StaleRevision,
    onStatus: (status) => statuses.push(status),
  });
  saver.setTarget({ send: server.send, onSaved: (revision) => saved.push(revision) });
  return { saver, statuses, saved };
}

describe("DraftSaver", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it("does nothing before the draft is loaded", async () => {
    const server = fakeServer();
    const { saver } = makeSaver(server);
    saver.schedule({ title: "empty editor" });
    await vi.runAllTimersAsync();
    expect(server.state.saves).toEqual([]);
  });

  it("debounces edits into one save", async () => {
    const server = fakeServer();
    const { saver, saved } = makeSaver(server);
    saver.start(3);
    saver.schedule({ title: "F" });
    saver.schedule({ title: "Fr" });
    saver.schedule({ title: "Fran" });
    await vi.runAllTimersAsync();
    expect(server.state.saves).toEqual([{ title: "Fran", expected_source_revision: 3 }]);
    expect(saved).toEqual([4]);
  });

  it("never overlaps saves and sends each with the revision the previous one returned", async () => {
    // The bug ANR hit: a save slower than the autosave delay while typing on.
    const server = fakeServer({ latencyMs: 1_500 });
    const { saver, statuses } = makeSaver(server);
    saver.start(3);
    saver.schedule({ title: "sdfds" });
    await vi.advanceTimersByTimeAsync(1_100);
    saver.schedule({ title: "sdfds efes" });
    await vi.advanceTimersByTimeAsync(1_100);
    saver.schedule({ title: "sdfds efes!" });
    await vi.runAllTimersAsync();

    expect(server.state.maxInFlight).toBe(1);
    // Edits made while a save runs are coalesced into the next one.
    expect(server.state.saves).toEqual([
      { title: "sdfds", expected_source_revision: 3 },
      { title: "sdfds efes!", expected_source_revision: 4 },
    ]);
    expect(statuses).not.toContain("conflict");
    expect(statuses.at(-1)).toBe("saved");
  });

  it("skips content the server already has", async () => {
    const server = fakeServer();
    const { saver } = makeSaver(server);
    saver.start(3);
    saver.schedule({ title: "Fran" });
    await vi.runAllTimersAsync();
    // e.g. a new sign-in token re-renders the editor with the same content
    saver.schedule({ title: "Fran" });
    await vi.runAllTimersAsync();
    expect(server.state.saves).toHaveLength(1);
  });

  it("runs an explicit save and the follow-up step after the save already running", async () => {
    const server = fakeServer({ latencyMs: 500 });
    const { saver } = makeSaver(server);
    saver.start(3);
    saver.schedule({ title: "draft" });
    await vi.advanceTimersByTimeAsync(1_100); // autosave now in flight
    const order: string[] = [];
    const publishing = saver.saveNow({ title: "final" }, async (revision) => {
      order.push(`publish@${revision}`);
    });
    await vi.runAllTimersAsync();
    await publishing;
    expect(server.state.saves.map((save) => save.title)).toEqual(["draft", "final"]);
    expect(order).toEqual(["publish@5"]);
  });

  it("stops on a real conflict, keeps the content, and saves it over the newer revision on request", async () => {
    const server = fakeServer();
    const { saver, statuses } = makeSaver(server);
    saver.start(3);
    server.state.revision = 7; // saved in another tab
    saver.schedule({ title: "mine" });
    await vi.runAllTimersAsync();
    expect(statuses.at(-1)).toBe("conflict");
    expect(saver.hasConflict).toBe(true);

    // Edits made while the notice is up are kept but not sent.
    saver.schedule({ title: "mine, edited" });
    await vi.runAllTimersAsync();
    expect(server.state.saves).toEqual([]);
    await expect(saver.saveNow({ title: "publish" })).rejects.toBeInstanceOf(DraftConflictError);

    saver.schedule({ title: "mine, final" });
    await expect(saver.overwrite(7)).resolves.toBe(8);
    expect(server.state.saves).toEqual([{ title: "mine, final", expected_source_revision: 7 }]);
    expect(statuses.at(-1)).toBe("saved");
  });

  it("starts over from the loaded revision when the coach loads the other version", async () => {
    const server = fakeServer();
    const { saver } = makeSaver(server);
    saver.start(3);
    server.state.revision = 7;
    saver.schedule({ title: "mine" });
    await vi.runAllTimersAsync();
    expect(saver.hasConflict).toBe(true);

    saver.start(7);
    saver.schedule({ title: "theirs, edited" });
    await vi.runAllTimersAsync();
    expect(server.state.saves).toEqual([{ title: "theirs, edited", expected_source_revision: 7 }]);
  });

  it("retries a failed save on its own", async () => {
    let failNext = true;
    const server = fakeServer();
    const { saver, statuses } = makeSaver(server);
    saver.setTarget({
      send: (payload) => {
        if (failNext) {
          failNext = false;
          return Promise.reject(new Error("offline"));
        }
        return server.send(payload);
      },
    });
    saver.start(3);
    saver.schedule({ title: "Fran" });
    await vi.advanceTimersByTimeAsync(1_100);
    expect(statuses.at(-1)).toBe("error");
    await vi.runAllTimersAsync();
    expect(server.state.saves).toEqual([{ title: "Fran", expected_source_revision: 3 }]);
    expect(statuses.at(-1)).toBe("saved");
  });

  it("sends nothing after it is closed", async () => {
    const server = fakeServer();
    const { saver } = makeSaver(server);
    saver.start(3);
    saver.schedule({ title: "Fran" });
    saver.close();
    saver.schedule({ title: "Fran 2" });
    await vi.runAllTimersAsync();
    expect(server.state.saves).toEqual([]);
  });
});
