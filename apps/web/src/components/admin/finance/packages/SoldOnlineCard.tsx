"use client";

import Link from "next/link";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { updateFinancePackage, type FinanceRecord } from "@/api/finance";
import { Toggle } from "@/components/admin/finance/packages/package-ui";
import { PAYMENT_ACCOUNT_KEY } from "@/components/admin/payments/OnlinePaymentsSettings";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

import { canSellOnline, fixLink, isHidden, isSoldOnline, onlineVisibility } from "./sold-online";

/**
 * «Πώληση» in the package panel's «Προχωρημένες ρυθμίσεις» (ADR-271, mockup
 * p1 option A): one switch, saved at once, and a line that says whether box
 * members see the package online and, if not, why, with a link to fix it.
 * Switching is the owner's choice: Palee never turns it back on by itself.
 */
export function SoldOnlineCard({ token, pkg }: { token: string; pkg: FinanceRecord }) {
  const t = useTranslations("SoldOnline");
  const ui = useUiTranslations();
  const slug = useOrganizationSlug();
  const queryClient = useQueryClient();
  const packageId = String(pkg.id ?? "");

  const mutation = useMutation({
    mutationFn: (value: boolean) => updateFinancePackage(token, packageId, { sold_online: value }),
    onSuccess: async (data) => {
      queryClient.setQueryData(["admin", "finance", "package", packageId], data);
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ["admin", "finance", "packages"] }),
        queryClient.invalidateQueries({ queryKey: PAYMENT_ACCOUNT_KEY }),
      ]);
    },
  });

  const visibility = onlineVisibility(pkg);
  const on = isSoldOnline(pkg);
  const fix = on ? fixLink(visibility) : null;
  const warn = on && isHidden(visibility);

  return (
    <section
      className="space-y-2 rounded-2xl px-4 py-3"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      data-testid="sold-online-card"
    >
      <h4 className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("sale")}</h4>
      <div className="flex items-center gap-3">
        <div className="min-w-0 flex-1">
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("title")}</p>
          <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>{t("subtitle")}</p>
        </div>
        <Toggle
          label={t("title")}
          checked={on && canSellOnline(visibility)}
          disabled={!canSellOnline(visibility) || mutation.isPending}
          onChange={(value) => mutation.mutate(value)}
        />
      </div>
      <p className="text-xs leading-5" style={{ color: warn ? "var(--warning)" : "var(--dim)" }} data-testid="sold-online-hint">
        {t(`hint_${visibility}`)}
        {fix ? (
          <>
            {" "}
            <Link href={adminHref(fix.href, slug)} className="font-semibold underline" style={{ color: "var(--primary)" }}>
              {t(fix.labelKey)} ›
            </Link>
          </>
        ) : null}
      </p>
      {mutation.isSuccess && !mutation.isPending ? (
        <p role="status" className="text-xs font-semibold" style={{ color: "var(--success)" }}>
          ✓ {t("saved")}
        </p>
      ) : null}
      {mutation.isError ? <ErrorNotice variant="field">{localizeError(mutation.error, ui)}</ErrorNotice> : null}
    </section>
  );
}
