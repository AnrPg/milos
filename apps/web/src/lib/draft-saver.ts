/**
 * Saves a workout draft one request at a time.
 *
 * Every draft save carries the source revision it was based on and the API
 * refuses a save whose revision is out of date (`stale_dsl_revision`), so
 * two saves of the same editor must never overlap: the second would carry
 * the revision the first one just replaced. The saver keeps one queue per
 * editor, reads the revision when a request is sent (never when it is
 * scheduled), skips saves of content the server already has, and stops
 * saving once the draft really changed somewhere else, until the coach
 * chooses which version to keep.
 */

export type DraftSaveStatus = "idle" | "saving" | "saved" | "error" | "conflict";

export type DraftSaveResult = { dsl_source_revision?: number | null };

export type DraftSaverOptions = {
  /** Whether an error means the draft changed somewhere else. */
  isConflict: (error: unknown) => boolean;
  onStatus?: (status: DraftSaveStatus) => void;
  delayMs?: number;
};

export type DraftSaverTarget<P extends object> = {
  /** Sends one save; the payload already carries `expected_source_revision`. */
  send: (payload: P & { expected_source_revision: number }) => Promise<DraftSaveResult>;
  /** Called after each save the server accepted. */
  onSaved?: (revision: number) => void;
};

export const DRAFT_AUTOSAVE_DELAY_MS = 1_000;
/** A failed autosave (offline, server error) is retried, waiting longer each time. */
const RETRY_DELAYS_MS = [2_000, 5_000, 15_000, 30_000, 60_000];

export class DraftConflictError extends Error {
  constructor() {
    super("The draft changed somewhere else.");
    this.name = "DraftConflictError";
  }
}

export class DraftSaver<P extends object> {
  private revision: number | null = null;
  private queue: Promise<unknown> = Promise.resolve();
  private timer: ReturnType<typeof setTimeout> | null = null;
  /** The newest content not sent yet (scheduled, or refused by a conflict). */
  private pending: P | null = null;
  /** The content the server has, as sent; equal content is not sent again. */
  private savedKey: string | null = null;
  private conflicted = false;
  private closed = false;
  private failures = 0;

  private target: DraftSaverTarget<P> | null = null;

  constructor(private readonly options: DraftSaverOptions) {}

  /** Where saves go (the editor's current session and draft). */
  setTarget(target: DraftSaverTarget<P>) {
    this.target = target;
  }

  /** Arms the saver with the revision the editor loaded. */
  start(revision: number) {
    this.cancelTimer();
    this.revision = revision;
    this.pending = null;
    this.savedKey = null;
    this.conflicted = false;
    this.failures = 0;
    this.options.onStatus?.("idle");
  }

  get started() {
    return this.revision !== null;
  }

  get currentRevision() {
    return this.revision;
  }

  get hasConflict() {
    return this.conflicted;
  }

  /** Saves `payload` after the autosave delay; a newer call replaces it. */
  schedule(payload: P) {
    if (!this.started || this.closed) return;
    this.pending = payload;
    if (this.conflicted) return;
    this.arm(this.options.delayMs ?? DRAFT_AUTOSAVE_DELAY_MS);
  }

  /**
   * Sends what is still waiting, after any save already running.
   * Resolves with the revision the server holds afterwards.
   */
  flush(): Promise<number> {
    this.cancelTimer();
    return this.enqueue(async () => {
      const payload = this.pending;
      this.pending = null;
      if (payload) await this.send(payload);
      return this.requireRevision();
    });
  }

  /**
   * Saves `payload` now, behind any save already running, then runs `after`
   * with the new revision before any later save may start. Used by publish
   * and mode switches, which must act on exactly what they saved.
   */
  saveNow<T = void>(payload: P, after?: (revision: number) => Promise<T>): Promise<T | number> {
    this.cancelTimer();
    // The explicit save supersedes anything that was waiting.
    this.pending = null;
    return this.enqueue(async () => {
      await this.send(payload);
      const revision = this.requireRevision();
      return after ? after(revision) : revision;
    });
  }

  /**
   * The coach keeps their own version over the one saved elsewhere: the
   * waiting content is saved on top of `latestRevision`.
   */
  overwrite(latestRevision: number): Promise<number> {
    this.revision = latestRevision;
    this.conflicted = false;
    // The server copy differs from what was last sent from here.
    this.savedKey = null;
    return this.flush();
  }

  /** Lets a closed saver save again (React re-mounts an editor in development). */
  reopen() {
    this.closed = false;
  }

  /** Stops saving (the editor published or is going away). */
  close() {
    this.closed = true;
    this.cancelTimer();
    this.pending = null;
  }

  private enqueue<T>(task: () => Promise<T>): Promise<T> {
    const run = this.queue.then(task);
    // A failed save must not block the ones after it.
    this.queue = run.catch(() => undefined);
    return run;
  }

  private async send(payload: P) {
    if (this.conflicted) {
      this.pending = payload;
      throw new DraftConflictError();
    }
    const key = JSON.stringify(payload);
    if (key === this.savedKey) return;

    const expected = this.requireRevision();
    this.options.onStatus?.("saving");
    try {
      if (!this.target) throw new Error("The draft saver has nowhere to save.");
      const result = await this.target.send({ ...payload, expected_source_revision: expected });
      const next = typeof result.dsl_source_revision === "number" ? result.dsl_source_revision : expected + 1;
      this.revision = next;
      this.savedKey = key;
      this.failures = 0;
      if (!this.closed) {
        this.options.onStatus?.("saved");
        this.target?.onSaved?.(next);
      }
    } catch (error) {
      // Keep the content so a retry (or "keep my version") sends it.
      this.pending ??= payload;
      if (this.options.isConflict(error)) {
        this.conflicted = true;
        this.cancelTimer();
        if (!this.closed) this.options.onStatus?.("conflict");
        throw new DraftConflictError();
      }
      if (!this.closed) {
        this.options.onStatus?.("error");
        if (this.timer === null) {
          this.arm(RETRY_DELAYS_MS[Math.min(this.failures, RETRY_DELAYS_MS.length - 1)]!);
        }
        this.failures += 1;
      }
      throw error;
    }
  }

  private requireRevision() {
    if (this.revision === null) throw new Error("The draft saver was used before the draft loaded.");
    return this.revision;
  }

  private arm(delayMs: number) {
    this.cancelTimer();
    this.timer = setTimeout(() => {
      this.timer = null;
      void this.flush().catch(() => undefined);
    }, delayMs);
  }

  private cancelTimer() {
    if (this.timer === null) return;
    clearTimeout(this.timer);
    this.timer = null;
  }
}
