"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useRouter } from "next/navigation";

import { fetchGymStaff } from "@/api/staff";
import { archiveOrganization, createOwnedOrganization, transferOwnership } from "@/api/roles";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { rememberSelectedOrganization } from "@/lib/organization-slug";

const field = "w-full rounded-2xl px-4 py-3 text-sm";
const fieldStyle = { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" };
const button = "rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50";

/** The owner's gym actions: new gym, hand over ownership, archive (ADR-099). */
export function OrganizationOwnerSettings({ token, slug, currentUserId }: { token: string; slug: string | null; currentUserId?: string }) {
  const i18n = useUiTranslations();
  const router = useRouter();
  const queryClient = useQueryClient();
  const [name, setName] = useState("");
  const [newOwner, setNewOwner] = useState("");
  const [confirm, setConfirm] = useState("");
  const staff = useQuery({ queryKey: ["staff", "members"], queryFn: () => fetchGymStaff(token) });
  const done = () => queryClient.invalidateQueries({ queryKey: ["organization-memberships"] });

  const create = useMutation({
    mutationFn: () => createOwnedOrganization(token, name.trim()),
    onSuccess: async (organization) => {
      await done();
      rememberSelectedOrganization(organization.slug);
      router.push(`/org/${organization.slug}/admin`);
    },
  });
  const transfer = useMutation({ mutationFn: () => transferOwnership(token, newOwner), onSuccess: done });
  const archive = useMutation({
    mutationFn: () => archiveOrganization(token, confirm.trim()),
    onSuccess: async () => {
      await done();
      router.push("/");
    },
  });
  const candidates = (staff.data ?? []).filter((member) => member.user_id !== currentUserId);

  return (
    <div className="space-y-8">
      <form
        className="space-y-3"
        onSubmit={(event) => {
          event.preventDefault();
          if (name.trim().length >= 2) create.mutate();
        }}
      >
        <h3 className="text-sm font-semibold" style={{ color: "var(--text)" }}>{i18n("orgCreateTitle")}</h3>
        <p className="text-xs" style={{ color: "var(--dim)" }}>{i18n("orgCreateHelp")}</p>
        <input className={field} style={fieldStyle} value={name} onChange={(event) => setName(event.target.value)} aria-label={i18n("orgCreateName")} placeholder={i18n("orgCreateName")} />
        <button type="submit" className={button} disabled={create.isPending || name.trim().length < 2} style={{ background: "var(--text)", color: "var(--bg)" }}>
          {i18n("orgCreateAction")}
        </button>
        {create.isError ? <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{localizeError(create.error, i18n)}</p> : null}
      </form>

      <form
        className="space-y-3"
        onSubmit={(event) => {
          event.preventDefault();
          if (newOwner && window.confirm(i18n("orgTransferConfirm"))) transfer.mutate();
        }}
      >
        <h3 className="text-sm font-semibold" style={{ color: "var(--text)" }}>{i18n("orgTransferTitle")}</h3>
        <p className="text-xs" style={{ color: "var(--dim)" }}>{i18n("orgTransferHelp")}</p>
        <select className={field} style={fieldStyle} value={newOwner} onChange={(event) => setNewOwner(event.target.value)} aria-label={i18n("orgTransferTitle")}>
          <option value="">{i18n("orgTransferChoose")}</option>
          {candidates.map((member) => (
            <option key={member.user_id} value={member.user_id}>{member.nickname}</option>
          ))}
        </select>
        <button type="submit" className={button} disabled={!newOwner || transfer.isPending} style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}>
          {i18n("orgTransferAction")}
        </button>
        {transfer.isSuccess ? <p className="text-sm" style={{ color: "var(--success, var(--primary))" }}>{i18n("orgTransferDone")}</p> : null}
        {transfer.isError ? <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{localizeError(transfer.error, i18n)}</p> : null}
      </form>

      <form
        className="space-y-3 rounded-2xl p-4"
        style={{ border: "1px solid color-mix(in srgb, var(--danger) 40%, transparent)" }}
        onSubmit={(event) => {
          event.preventDefault();
          if (confirm.trim() === slug) archive.mutate();
        }}
      >
        <h3 className="text-sm font-semibold" style={{ color: "var(--danger)" }}>{i18n("orgArchiveTitle")}</h3>
        <p className="text-xs" style={{ color: "var(--dim)" }}>{i18n("orgArchiveHelp", { slug: slug ?? "" })}</p>
        <input className={field} style={fieldStyle} value={confirm} onChange={(event) => setConfirm(event.target.value)} aria-label={i18n("orgArchiveConfirmLabel")} placeholder={slug ?? ""} />
        <button type="submit" className={button} disabled={confirm.trim() !== slug || archive.isPending} style={{ background: "var(--danger)", color: "var(--danger-contrast)" }}>
          {i18n("orgArchiveAction")}
        </button>
        {archive.isError ? <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{localizeError(archive.error, i18n)}</p> : null}
      </form>
    </div>
  );
}
