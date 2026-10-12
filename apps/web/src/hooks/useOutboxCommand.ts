"use client";

import { useCallback } from "react";

import { currentOrganizationSlug } from "@/api/client";
import { useSession } from "@/components/session-provider";
import { getOutboxCommandAdapter } from "@/lib/offline-command-adapters";
import {
  defaultCommandStore,
  submitOutboxCommand,
  type OutboxCommandKind,
  type SubmitCommandResult,
} from "@/lib/offline-command-outbox";

/**
 * Submits one of the explicitly registered ADR-102 commands through the
 * durable device outbox, pinned to the current user and organization.
 */
export function useOutboxCommand() {
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token ?? null;
  const userId = currentUser?.id ?? null;

  return useCallback(
    async <Result, Payload>(
      kind: OutboxCommandKind,
      payload: Payload,
    ): Promise<SubmitCommandResult<Result>> => {
      if (!token) throw new Error("missing_session");

      return submitOutboxCommand<Result, Payload>({
        token,
        // Without a resolved user there is no safe owner for a durable record:
        // send directly instead of queuing.
        ownerUserId: userId ?? "",
        organizationSlug: currentOrganizationSlug(token),
        kind,
        payload,
        lookup: getOutboxCommandAdapter,
        store: userId ? defaultCommandStore() : null,
      });
    },
    [token, userId],
  );
}
