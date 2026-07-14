"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useRouter, useSearchParams } from "next/navigation";
import { useCallback } from "react";

import {
  createReferralReward,
  createReferralProgram,
  fetchReferralEvents,
  fetchReferralPrograms,
  fetchReferralRewards,
  updateReferralProgram,
  updateReferralEventStatus,
  updateReferralRewardStatus,
  type FinanceRecord,
} from "@/api/finance";
import { useSession } from "@/components/session-provider";
import { SidePanel } from "@/components/admin/finance/shared/SidePanel";
import { ReferralEventWizard } from "@/components/admin/finance/ReferralEventWizard";

function field(record: FinanceRecord | null | undefined, key: string, fallback = "") {
  const value = record?.[key];
  if (value === null || value === undefined) return fallback;
  return String(value);
}

const BLANK_PROGRAM = { name: "", description: "", reward_type: "credit", reward_value: "0", active: true };

function programFormFromRecord(program: FinanceRecord | null | undefined) {
  return {
    name: field(program, "name"),
    description: field(program, "description"),
    reward_type: field(program, "reward_type", "manual"),
    reward_value: field(program, "reward_value", "0"),
    active: program?.active !== false,
  };
}

function displayName(record: FinanceRecord | null | undefined, labelKey: string, idKey: string) {
  return field(record, labelKey, field(record, idKey).slice(0, 8));
}

function rewardStatusText(status: string) {
  if (status === "applied") return "Approved";
  if (status === "rejected") return "Rejected";
  if (status === "approved") return "Ready to approve";
  return "Pending review";
}

function eventStatusText(status: string) {
  if (status === "approved" || status === "applied") return "Referral confirmed";
  if (status === "rejected") return "Referral rejected";
  return "Referral pending";
}

function rewardDescriptor(reward: FinanceRecord | null | undefined) {
  if (!reward) return "Not issued";
  return `${field(reward, "reward_type")} · ${field(reward, "reward_value")}`;
}

function eventRewardStatusText(
  event: FinanceRecord | null | undefined,
  reward: FinanceRecord | null | undefined,
) {
  if (reward) return `Reward ${rewardStatusText(field(reward, "status")).toLowerCase()}`;
  if (field(event, "status") === "rejected") return "No reward";
  return "Reward not issued";
}

function eventRewardPillStyle(
  event: FinanceRecord | null | undefined,
  reward: FinanceRecord | null | undefined,
) {
  const status = reward ? field(reward, "status") : field(event, "status");

  if (status === "applied") return { background: "color-mix(in srgb, var(--success) 12%, transparent)", color: "var(--success)" };
  if (status === "rejected") return { background: "color-mix(in srgb, var(--primary) 12%, transparent)", color: "var(--primary)" };
  if (status === "pending" || status === "approved") return { background: "var(--border)", color: "var(--text-soft)" };
  return { background: "var(--border)", color: "var(--dim)" };
}

export function ReferralsTab() {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const router = useRouter();
  const searchParams = useSearchParams();

  const showNewProgram = searchParams.get("new") === "program";
  const showNewEvent = searchParams.get("new-event") === "true";
  const selectedProgramId = searchParams.get("referral-program");
  const selectedEventId = searchParams.get("referral-event");
  const selectedRewardId = searchParams.get("referral-reward");

  const setParam = useCallback(
    (updates: Record<string, string | null>) => {
      const params = new URLSearchParams(searchParams.toString());
      Object.entries(updates).forEach(([k, v]) => {
        if (v === null) params.delete(k);
        else params.set(k, v);
      });
      router.replace(`?${params.toString()}`, { scroll: false });
    },
    [router, searchParams],
  );

  const programsQuery = useQuery({
    queryKey: ["admin", "finance", "referral-programs"],
    enabled: Boolean(token),
    queryFn: () => fetchReferralPrograms(token),
  });

  const eventsQuery = useQuery({
    queryKey: ["admin", "finance", "referrals"],
    enabled: Boolean(token),
    queryFn: () => fetchReferralEvents(token),
  });

  const rewardsQuery = useQuery({
    queryKey: ["admin", "finance", "referral-rewards"],
    enabled: Boolean(token),
    queryFn: () => fetchReferralRewards(token),
  });

  const programs = programsQuery.data?.referral_programs ?? [];
  const events = eventsQuery.data?.referral_events ?? [];
  const rewards = rewardsQuery.data?.referral_rewards ?? [];
  const selectedProgram = programs.find((program) => field(program, "id") === selectedProgramId);
  const selectedEvent = events.find((event) => field(event, "id") === selectedEventId);
  const selectedReward = rewards.find((reward) => field(reward, "id") === selectedRewardId);
  const selectedEventProgram = programs.find(
    (program) => field(program, "id") === field(selectedEvent, "referral_program_id"),
  );
  const selectedEventReward = rewards.find(
    (reward) => field(reward, "referral_event_id") === field(selectedEvent, "id"),
  );

  const [programForm, setProgramForm] = useState(BLANK_PROGRAM);
  const [programEditForm, setProgramEditForm] = useState(BLANK_PROGRAM);
  const selectedProgramDefaults = selectedProgram ? programFormFromRecord(selectedProgram) : BLANK_PROGRAM;
  const activeProgramEditForm = programEditForm.name ? programEditForm : selectedProgramDefaults;

  const createProgramMutation = useMutation({
    mutationFn: () =>
      createReferralProgram(token, {
        ...programForm,
        reward_value: Number(programForm.reward_value || 0),
      }),
    onSuccess: async () => {
      setProgramForm(BLANK_PROGRAM);
      setParam({ new: null });
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "referral-programs"] });
    },
  });

  const updateProgramMutation = useMutation({
    mutationFn: () =>
      updateReferralProgram(token, field(selectedProgram, "id"), {
        ...activeProgramEditForm,
        reward_value: Number(activeProgramEditForm.reward_value || 0),
      }),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "referral-programs"] });
    },
  });

  const updateEventMutation = useMutation({
    mutationFn: ({ id, status }: { id: string; status: string }) => updateReferralEventStatus(token, id, status),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "referrals"] });
    },
  });

  const createRewardMutation = useMutation({
    mutationFn: ({ event, program }: { event: FinanceRecord; program: FinanceRecord | undefined }) =>
      createReferralReward(token, field(event, "id"), {
        reward_type: field(program, "reward_type", "manual"),
        reward_value: Number(field(program, "reward_value", "0")),
      }),
    onSuccess: async (data) => {
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "referral-rewards"] });
      setParam({
        "referral-event": null,
        "referral-reward": field(data.referral_reward, "id"),
      });
    },
  });

  const updateRewardMutation = useMutation({
    mutationFn: ({ id, status }: { id: string; status: string }) => updateReferralRewardStatus(token, id, status),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "referrals"] });
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "referral-rewards"] });
    },
  });

  return (
    <div className="space-y-10">

      {/* Programs */}
      <Section
        title="Programs"
        count={programs.length}
        onNew={() => setParam({ new: "program" })}
        newLabel="+ New program"
      >
        {programsQuery.isLoading ? (
          <EmptyRow>Loading…</EmptyRow>
        ) : programs.length === 0 ? (
          <EmptyRow>No referral programs yet.</EmptyRow>
        ) : (
          programs.map((p, i) => (
            <ListRow
              key={field(p, "id")}
              last={i === programs.length - 1}
              onClick={() => {
                setProgramEditForm(programFormFromRecord(p));
                setParam({ "referral-program": field(p, "id") });
              }}
            >
              <div>
                <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{field(p, "name")}</p>
                <p className="mt-0.5 text-xs" style={{ color: "var(--dim)" }}>
                  {field(p, "reward_type")} · {field(p, "reward_value")} ·{" "}
                  {p.active !== false ? "Active" : "Inactive"}
                </p>
              </div>
              <StatusBadge active={p.active !== false} />
            </ListRow>
          ))
        )}
      </Section>

      {/* Events */}
      <Section
        title="Events"
        count={events.length}
        onNew={() => setParam({ "new-event": "true" })}
        newLabel="+ New event"
      >
        {eventsQuery.isLoading ? (
          <EmptyRow>Loading…</EmptyRow>
        ) : events.length === 0 ? (
          <EmptyRow>No referral events yet.</EmptyRow>
        ) : (
          events.map((e, i) => {
            const eventReward = rewards.find((reward) => field(reward, "referral_event_id") === field(e, "id"));

            return (
              <ListRow
                key={field(e, "id")}
                last={i === events.length - 1}
                onClick={() => setParam({ "referral-event": field(e, "id") })}
              >
                <div className="min-w-0">
                  <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                    {field(e, "label")}
                  </p>
                  <p className="mt-0.5 text-xs" style={{ color: "var(--dim)" }}>
                    {field(e, "program_name")} · {eventStatusText(field(e, "status"))} · {eventRewardStatusText(e, eventReward)}
                  </p>
                </div>
                <div className="flex flex-wrap gap-2">
                  {field(e, "status") === "pending" && (
                    <>
                      <StatusButton
                        label="Approve"
                        pending={updateEventMutation.isPending}
                        onClick={(event) => {
                          event.stopPropagation();
                          updateEventMutation.mutate({ id: field(e, "id"), status: "approved" });
                        }}
                      />
                      <StatusButton
                        label="Reject"
                        pending={updateEventMutation.isPending}
                        danger
                        onClick={(event) => {
                          event.stopPropagation();
                          updateEventMutation.mutate({ id: field(e, "id"), status: "rejected" });
                        }}
                      />
                    </>
                  )}
                  {field(e, "status") !== "pending" ? (
                    <span className="rounded-full px-3 py-1 text-xs font-semibold" style={eventRewardPillStyle(e, eventReward)}>
                      {eventRewardStatusText(e, eventReward)}
                    </span>
                  ) : null}
                </div>
              </ListRow>
            );
          })
        )}
      </Section>

      {/* Rewards */}
      <Section title="Rewards" count={rewards.length}>
        {rewardsQuery.isLoading ? (
          <EmptyRow>Loading…</EmptyRow>
        ) : rewards.length === 0 ? (
          <EmptyRow>No rewards yet. Approve a referral event to issue rewards.</EmptyRow>
        ) : (
          rewards.map((r, i) => (
            <ListRow
              key={field(r, "id")}
              last={i === rewards.length - 1}
              onClick={() => setParam({ "referral-reward": field(r, "id") })}
            >
              <div>
                <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                  {field(r, "reward_type")} · {field(r, "reward_value")}
                </p>
                <p className="mt-0.5 text-xs" style={{ color: "var(--dim)" }}>
                  {displayName(r, "recipient_nickname", "recipient_user_id")} · {rewardStatusText(field(r, "status"))}
                </p>
              </div>
              <div className="flex flex-wrap gap-2">
                {[
                  ["Approve", "applied"],
                  ["Reject", "rejected"],
                ].map(([label, status]) => (
                  <StatusButton
                    key={status}
                    label={label}
                    pending={updateRewardMutation.isPending}
                    disabled={field(r, "status") === status}
                    danger={status === "rejected"}
                    onClick={(event) => {
                      event.stopPropagation();
                      updateRewardMutation.mutate({ id: field(r, "id"), status });
                    }}
                  />
                ))}
              </div>
            </ListRow>
          ))
        )}
      </Section>

      {/* New Program side panel */}
      {showNewProgram ? (
        <SidePanel
          title="New referral program"
          subtitle="Referrals"
          onClose={() => setParam({ new: null })}
          footer={
            <div className="flex gap-3">
              <button
                className="rounded-full px-5 py-2 text-sm font-semibold disabled:opacity-50"
                style={{ background: "var(--text)", color: "var(--bg)" }}
                disabled={createProgramMutation.isPending || !programForm.name}
                onClick={() => createProgramMutation.mutate()}
                type="button"
              >
                {createProgramMutation.isPending ? "Creating…" : "Create program"}
              </button>
              <button
                className="rounded-full px-5 py-2 text-sm font-semibold"
                style={{ background: "var(--border)", color: "var(--text-soft)" }}
                onClick={() => setParam({ new: null })}
                type="button"
              >
                Cancel
              </button>
            </div>
          }
        >
          <div className="space-y-4">
            <PanelField label="Program name">
              <input
                className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                value={programForm.name}
                onChange={(e) => setProgramForm({ ...programForm, name: e.target.value })}
              />
            </PanelField>
            <PanelField label="Description">
              <input
                className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                value={programForm.description}
                onChange={(e) => setProgramForm({ ...programForm, description: e.target.value })}
              />
            </PanelField>
            <div className="grid gap-3 md:grid-cols-2">
              <PanelField label="Reward type">
                <select
                  className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                  value={programForm.reward_type}
                  onChange={(e) => setProgramForm({ ...programForm, reward_type: e.target.value })}
                >
                  {["credit", "discount", "free_period", "manual"].map((v) => (
                    <option key={v} value={v}>{v}</option>
                  ))}
                </select>
              </PanelField>
              <PanelField label="Reward value">
                <input
                  className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                  type="number"
                  value={programForm.reward_value}
                  onChange={(e) => setProgramForm({ ...programForm, reward_value: e.target.value })}
                />
              </PanelField>
            </div>
            <label className="flex items-center gap-3 text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
              <input
                type="checkbox"
                checked={programForm.active}
                onChange={(e) => setProgramForm({ ...programForm, active: e.target.checked })}
              />
              Active
            </label>
            {createProgramMutation.error instanceof Error && (
              <p className="text-sm" style={{ color: "var(--primary-strong)" }}>{createProgramMutation.error.message}</p>
            )}
          </div>
        </SidePanel>
      ) : null}

      {/* New Event wizard */}
      {showNewEvent ? (
        <ReferralEventWizard
          programs={programs}
          onClose={() => setParam({ "new-event": null })}
        />
      ) : null}

      {selectedProgram ? (
        <SidePanel
          title={field(selectedProgram, "name", "Referral program")}
          subtitle="Program details"
          onClose={() => setParam({ "referral-program": null })}
          footer={
            <PanelActions>
              <StatusButton
                label={updateProgramMutation.isPending ? "Saving..." : "Save changes"}
                pending={updateProgramMutation.isPending}
                disabled={!activeProgramEditForm.name}
                onClick={() => updateProgramMutation.mutate()}
              />
              <StatusButton
                label="Reset"
                pending={false}
                onClick={() => setProgramEditForm(programFormFromRecord(selectedProgram))}
              />
            </PanelActions>
          }
        >
          <div className="space-y-4">
            <PanelField label="Program name">
              <PanelInput
                value={activeProgramEditForm.name}
                onChange={(value) => setProgramEditForm({ ...activeProgramEditForm, name: value })}
              />
            </PanelField>
            <PanelField label="Description">
              <PanelInput
                value={activeProgramEditForm.description}
                onChange={(value) => setProgramEditForm({ ...activeProgramEditForm, description: value })}
              />
            </PanelField>
            <div className="grid gap-3 md:grid-cols-2">
              <PanelField label="Reward type">
                <PanelSelect
                  value={programEditForm.reward_type}
                  options={["credit", "discount", "free_period", "manual"]}
                  onChange={(value) => setProgramEditForm({ ...activeProgramEditForm, reward_type: value })}
                />
              </PanelField>
              <PanelField label="Reward value">
                <PanelInput
                  type="number"
                  value={activeProgramEditForm.reward_value}
                  onChange={(value) => setProgramEditForm({ ...activeProgramEditForm, reward_value: value })}
                />
              </PanelField>
            </div>
            <label className="flex items-center gap-3 text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
              <input
                type="checkbox"
                checked={activeProgramEditForm.active}
                onChange={(event) => setProgramEditForm({ ...activeProgramEditForm, active: event.target.checked })}
              />
              Active
            </label>
            <DetailGrid
              rows={[
                ["Program ID", field(selectedProgram, "id")],
                ["Created", dateText(selectedProgram.inserted_at)],
                ["Updated", dateText(selectedProgram.updated_at)],
              ]}
            />
            {updateProgramMutation.error instanceof Error ? (
              <p className="text-sm" style={{ color: "var(--primary-strong)" }}>{updateProgramMutation.error.message}</p>
            ) : null}
          </div>
        </SidePanel>
      ) : null}

      {selectedEvent ? (
        <SidePanel
          title={field(selectedEvent, "label")}
          subtitle="Referral event"
          onClose={() => setParam({ "referral-event": null })}
          footer={
            <PanelActions>
              {field(selectedEvent, "status") === "pending" ? (
                <>
                  <StatusButton
                    label="Approve"
                    pending={updateEventMutation.isPending}
                    onClick={() => updateEventMutation.mutate({ id: field(selectedEvent, "id"), status: "approved" })}
                  />
                  <StatusButton
                    label="Reject"
                    pending={updateEventMutation.isPending}
                    danger
                    onClick={() => updateEventMutation.mutate({ id: field(selectedEvent, "id"), status: "rejected" })}
                  />
                </>
              ) : null}
              {field(selectedEvent, "status") === "approved" && !selectedEventReward ? (
                <StatusButton
                  label="Create reward"
                  pending={createRewardMutation.isPending}
                  onClick={() => createRewardMutation.mutate({ event: selectedEvent, program: selectedEventProgram })}
                />
              ) : null}
              {selectedEventReward ? (
                <StatusButton
                  label="Open reward"
                  pending={false}
                  onClick={() =>
                    setParam({
                      "referral-event": null,
                      "referral-reward": field(selectedEventReward, "id"),
                    })
                  }
                />
              ) : null}
            </PanelActions>
          }
        >
          <DetailGrid
            rows={[
              ["Event ID", field(selectedEvent, "id")],
              ["Referral status", eventStatusText(field(selectedEvent, "status"))],
              ["Reward", rewardDescriptor(selectedEventReward)],
              ["Reward status", eventRewardStatusText(selectedEvent, selectedEventReward)],
              ["Program", field(selectedEventProgram, "name", field(selectedEvent, "referral_program_id"))],
              ["Referrer", displayName(selectedEvent, "referrer_nickname", "referrer_user_id")],
              ["Referred", displayName(selectedEvent, "referred_nickname", "referred_user_id")],
              ["Membership", field(selectedEvent, "membership_id")],
              ["Signup source", field(selectedEvent, "signup_source_snapshot", "referral")],
              ["Notes", field(selectedEvent, "notes", "No notes")],
              ["Created", dateText(selectedEvent.inserted_at)],
              ["Updated", dateText(selectedEvent.updated_at)],
            ]}
          />
          {createRewardMutation.error instanceof Error ? (
            <p className="text-sm" style={{ color: "var(--primary-strong)" }}>{createRewardMutation.error.message}</p>
          ) : null}
        </SidePanel>
      ) : null}

      {selectedReward ? (
        <SidePanel
          title={`${field(selectedReward, "reward_type")} · ${field(selectedReward, "reward_value")}`}
          subtitle="Referral reward"
          onClose={() => setParam({ "referral-reward": null })}
          footer={
            <PanelActions>
              {[
                ["Approve", "applied"],
                ["Reject", "rejected"],
              ].map(([label, status]) => (
                <StatusButton
                  key={status}
                  label={label}
                  pending={updateRewardMutation.isPending}
                  disabled={field(selectedReward, "status") === status}
                  danger={status === "rejected"}
                  onClick={() => updateRewardMutation.mutate({ id: field(selectedReward, "id"), status })}
                />
              ))}
            </PanelActions>
          }
        >
          <DetailGrid
            rows={[
              ["Reward ID", field(selectedReward, "id")],
              ["Status", rewardStatusText(field(selectedReward, "status"))],
              ["Referral", field(selectedReward, "referral_label", field(selectedReward, "referral_event_id"))],
              ["Recipient", displayName(selectedReward, "recipient_nickname", "recipient_user_id")],
              ["Membership", field(selectedReward, "membership_id")],
              ["Reward type", field(selectedReward, "reward_type")],
              ["Reward value", field(selectedReward, "reward_value")],
              ["Applied at", dateText(selectedReward.applied_at)],
              ["Created", dateText(selectedReward.inserted_at)],
              ["Updated", dateText(selectedReward.updated_at)],
            ]}
          />
          {field(selectedReward, "status") === "pending" || field(selectedReward, "status") === "approved" ? (
            <Notice tone="neutral">
              Approving this reward completes fulfillment. Credit rewards create a credit ledger grant for the
              recipient; manual, discount, and free-period rewards are recorded as fulfilled.
            </Notice>
          ) : null}
          {updateRewardMutation.error instanceof Error ? (
            <p className="text-sm" style={{ color: "var(--primary-strong)" }}>{updateRewardMutation.error.message}</p>
          ) : null}
        </SidePanel>
      ) : null}

    </div>
  );
}

function Section({
  title,
  count,
  onNew,
  newLabel,
  children,
}: {
  title: string;
  count: number;
  onNew?: () => void;
  newLabel?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between gap-4">
        <p className="text-sm font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>
          {title} ({count})
        </p>
        {onNew && (
          <button
            className="rounded-full px-4 py-2 text-sm font-semibold"
            style={{ background: "color-mix(in srgb, var(--primary) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 20%, transparent)", color: "var(--primary)" }}
            onClick={onNew}
            type="button"
          >
            {newLabel}
          </button>
        )}
      </div>
      <div className="rounded-[2rem] overflow-hidden" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        {children}
      </div>
    </div>
  );
}

function ListRow({
  children,
  last,
  onClick,
}: {
  children: React.ReactNode;
  last: boolean;
  onClick?: () => void;
}) {
  function handleKeyDown(event: React.KeyboardEvent<HTMLDivElement>) {
    if (!onClick) return;
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      onClick();
    }
  }

  return (
    <div
      className="flex w-full flex-wrap items-center justify-between gap-4 px-6 py-4 text-left transition-colors"
      role={onClick ? "button" : undefined}
      tabIndex={onClick ? 0 : undefined}
      style={{
        borderBottom: last ? "none" : "1px solid var(--border)",
        cursor: onClick ? "pointer" : "default",
      }}
      onClick={onClick}
      onKeyDown={handleKeyDown}
    >
      {children}
    </div>
  );
}

function EmptyRow({ children }: { children: React.ReactNode }) {
  return <p className="px-6 py-6 text-sm" style={{ color: "var(--dim)" }}>{children}</p>;
}

function StatusBadge({ active }: { active: boolean }) {
  return (
    <span
      className="rounded-full px-3 py-1 text-xs font-semibold"
      style={active ? { background: "color-mix(in srgb, var(--success) 12%, transparent)", color: "var(--success)" } : { background: "var(--border)", color: "var(--dim)" }}
    >
      {active ? "Active" : "Inactive"}
    </span>
  );
}

function StatusButton({
  label,
  pending,
  disabled,
  danger,
  onClick,
}: {
  label: string;
  pending: boolean;
  disabled?: boolean;
  danger?: boolean;
  onClick: (event: React.MouseEvent<HTMLButtonElement>) => void;
}) {
  return (
    <button
      className="rounded-full px-3 py-1 text-xs font-semibold capitalize disabled:opacity-40"
      style={
        danger
          ? { background: "color-mix(in srgb, var(--primary) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 30%, transparent)", color: "var(--primary)" }
          : { background: "var(--border)", border: "1px solid var(--border-strong)", color: "var(--text-soft)" }
      }
      disabled={pending || disabled}
      onClick={onClick}
      type="button"
    >
      {label}
    </button>
  );
}

function PanelField({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block space-y-1">
      <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{label}</span>
      {children}
    </label>
  );
}

function PanelInput({
  value,
  onChange,
  type = "text",
}: {
  value: string;
  onChange: (value: string) => void;
  type?: string;
}) {
  return (
    <input
      className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
      style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
      type={type}
      value={value}
      onChange={(event) => onChange(event.target.value)}
    />
  );
}

function PanelSelect({
  value,
  options,
  onChange,
}: {
  value: string;
  options: string[];
  onChange: (value: string) => void;
}) {
  return (
    <select
      className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
      style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
      value={value}
      onChange={(event) => onChange(event.target.value)}
    >
      {options.map((option) => (
        <option key={option} value={option}>{option}</option>
      ))}
    </select>
  );
}

function PanelActions({ children }: { children: React.ReactNode }) {
  return <div className="flex flex-wrap gap-3">{children}</div>;
}

function DetailGrid({ rows }: { rows: Array<[string, string]> }) {
  return (
    <div className="overflow-hidden rounded-[1.25rem]" style={{ border: "1px solid var(--border)" }}>
      {rows.map(([label, value], index) => (
        <div
          key={`${label}-${index}`}
          className="grid gap-2 px-4 py-3 text-sm md:grid-cols-[150px_1fr]"
          style={{ borderBottom: index === rows.length - 1 ? "none" : "1px solid var(--border)" }}
        >
          <span className="font-semibold uppercase tracking-[0.16em]" style={{ color: "var(--dim)", fontSize: 11 }}>
            {label}
          </span>
          <span className="break-words" style={{ color: "var(--text-soft)" }}>{value || "—"}</span>
        </div>
      ))}
    </div>
  );
}

function Notice({ children, tone = "warning" }: { children: React.ReactNode; tone?: "neutral" | "warning" }) {
  const style =
    tone === "neutral"
      ? { background: "color-mix(in srgb, var(--muted) 8%, transparent)", border: "1px solid color-mix(in srgb, var(--muted) 18%, transparent)", color: "var(--text-soft)" }
      : { background: "color-mix(in srgb, var(--primary) 8%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 22%, transparent)", color: "var(--text-soft)" };

  return (
    <p
      className="rounded-[1rem] px-4 py-3 text-sm leading-6"
      style={style}
    >
      {children}
    </p>
  );
}

function dateText(value: unknown) {
  if (!value) return "—";
  return String(value).slice(0, 10);
}
