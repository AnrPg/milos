"use client";





import {useUiTranslations} from "@/i18n/ui";
import Link from "next/link";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { fetchFinancePackage, updateFinancePackage, type FinanceRecord } from "@/api/finance";
import { useSession } from "@/components/session-provider";

function value(record: FinanceRecord | undefined, key: string, fallback = "") {
  const field = record?.[key];
  if (field === undefined || field === null) return fallback;
  return String(field);
}

export function AdminFinancePackageDetail({ packageId }: { packageId: string }) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const token = tokens?.access_token;
  const [formOverrides, setFormOverrides] = useState<
    Partial<{
      name: string;
      description: string;
      family: string;
      billing_period: string;
      base_price: string;
      tags: string;
      active: boolean;
    }>
  >({});

  const packageQuery = useQuery({
    queryKey: ["admin", "finance", "packages", packageId],
    enabled: Boolean(token),
    queryFn: async () => fetchFinancePackage(token!, packageId),
  });

  const packageRecord = packageQuery.data?.package;
  const form = {
    name: formOverrides.name ?? value(packageRecord, "name"),
    description: formOverrides.description ?? value(packageRecord, "description"),
    family: formOverrides.family ?? value(packageRecord, "family", "unlimited"),
    billing_period: formOverrides.billing_period ?? value(packageRecord, "billing_period", "monthly"),
    base_price: formOverrides.base_price ?? String(Number(packageRecord?.base_price_cents ?? 0) / 100),
    tags: formOverrides.tags ?? (Array.isArray(packageRecord?.tags) ? packageRecord.tags.join(", ") : ""),
    active: formOverrides.active ?? packageRecord?.active !== false,
  };

  const updateMutation = useMutation({
    mutationFn: async () =>
      updateFinancePackage(token!, packageId, {
        name: form.name,
        description: form.description,
        family: form.family,
        billing_period: form.billing_period,
        base_price_cents: Math.round(Number(form.base_price || 0) * 100),
        tags: form.tags
          .split(",")
          .map((tag) => tag.trim())
          .filter(Boolean),
        active: form.active,
      }),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance"] });
    },
  });

  return (
    <main className="min-h-screen bg-[var(--bg)] px-6 py-10 text-[var(--text)] md:px-10">
      <div className="mx-auto max-w-4xl space-y-6">
        <Link className="text-sm font-bold text-[var(--primary)]" href="/admin/finance">
          {i18n("backToFinance2de0820")}
        </Link>
        <section className="rounded-[2rem] border border-[var(--border)] bg-[var(--panel)] p-8">
          <p className="text-xs font-bold uppercase tracking-[0.24em] text-[var(--primary)]">{i18n("packageDetailb134a53")}</p>
          <h1 className="mt-3 text-4xl font-black">{value(packageRecord, "name", i18n("membershipPackage12e8323"))}</h1>
          <p className="mt-2 text-sm text-[var(--muted)]">
            {i18n("codeadac693")} {value(packageRecord, "code")} · {value(packageRecord, "family")} · {value(packageRecord, "billing_period")}
          </p>
        </section>

        <form
          className="space-y-4 rounded-[1.8rem] border border-[var(--border)] bg-[var(--panel)] p-6"
          onSubmit={(event) => {
            event.preventDefault();
            updateMutation.mutate();
          }}
        >
          <h2 className="text-xl font-black">{i18n("editPackage77c0543")}</h2>
          <Input label={i18n("name709a232")} value={form.name} onChange={(name) => setFormOverrides({ ...formOverrides, name })} />
          <Input
            label={i18n("description55f8ebc")}
            required={false}
            value={form.description}
            onChange={(description) => setFormOverrides({ ...formOverrides, description })}
          />
          <div className="grid gap-3 md:grid-cols-2">
            <Input
              label={i18n("family4efb6cb")}
              value={form.family}
              onChange={(family) => setFormOverrides({ ...formOverrides, family })}
            />
            <Select
              label={i18n("billingPeriodda59f5a")}
              value={form.billing_period}
              options={["monthly", "quarterly", "annual", "custom"]}
              onChange={(billing_period) => setFormOverrides({ ...formOverrides, billing_period })}
            />
          </div>
          <Input
            label={i18n("basePriceInEur4b30144")}
            type="number"
            value={form.base_price}
            onChange={(base_price) => setFormOverrides({ ...formOverrides, base_price })}
          />
          <Input
            label={i18n("tags848eed0")}
            required={false}
            value={form.tags}
            onChange={(tags) => setFormOverrides({ ...formOverrides, tags })}
          />
          <label className="flex items-center gap-3 text-sm font-bold">
            <input
              checked={form.active}
              type="checkbox"
              onChange={(event) => setFormOverrides({ ...formOverrides, active: event.target.checked })}
            />
            {i18n("activePackagebd72220")}
          </label>
          <button className="rounded-full bg-[var(--text)] px-5 py-3 text-sm font-bold text-[var(--primary-contrast)]" disabled={updateMutation.isPending} type="submit">
            {updateMutation.isPending ? i18n("savingae7e887") : i18n("savePackaged6e81a9")}
          </button>
          {updateMutation.error instanceof Error ? <p className="text-sm text-[var(--danger)]">{updateMutation.error.message}</p> : null}
        </form>
      </div>
    </main>
  );
}

function Select({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: string;
  options: string[];
  onChange: (value: string) => void;
}) {
  return (
    <label className="block space-y-1 text-sm font-semibold">
      <span>{label}</span>
      <select
        className="w-full rounded-2xl border border-[var(--border)] px-4 py-3"
        value={value}
        onChange={(event) => onChange(event.target.value)}
      >
        {options.map((option) => (
          <option key={option} value={option}>
            {option}
          </option>
        ))}
      </select>
    </label>
  );
}

function Input({
  label,
  value,
  onChange,
  required = true,
  type = "text",
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  required?: boolean;
  type?: string;
}) {
  
  return (
    <label className="block space-y-1 text-sm font-semibold">
      <span>{label}</span>
      <input
        className="w-full rounded-2xl border border-[var(--border)] px-4 py-3"
        required={required}
        type={type}
        value={value}
        onChange={(event) => onChange(event.target.value)}
      />
    </label>
  );
}
