"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import { primaryButtonClass, primaryButtonStyle, secondaryButtonClass, secondaryButtonStyle } from "@/components/staff/staff-ui";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

/**
 * The first visit: what the shop does and three steps. The steps are fixed
 * (principle 2): add a product, check the pickup point, then publish, which
 * is what opens the shop to members.
 */
export function ShopEmptyState() {
  const t = useTranslations("ShopConsole.empty");
  const organizationSlug = useOrganizationSlug();
  const steps = ["product", "pickup", "publish"] as const;

  return (
    <section
      aria-labelledby="shop-empty-title"
      className="flex flex-col gap-5 rounded-[2rem] p-6 md:p-8"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      data-testid="shop-empty"
    >
      <div className="flex flex-col gap-2">
        <h2 id="shop-empty-title" className="text-xl font-semibold" style={{ color: "var(--text)" }}>
          {t("title")}
        </h2>
        <p className="max-w-2xl text-sm" style={{ color: "var(--text-soft)" }}>
          {t("body")}
        </p>
      </div>
      <ol className="flex flex-col gap-2">
        {steps.map((step, index) => (
          <li key={step} className="flex items-start gap-3 rounded-2xl px-4 py-3" style={{ background: "var(--panel-muted)" }}>
            <span
              aria-hidden="true"
              className="inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-sm font-bold"
              style={{ background: "var(--panel)", border: "1px solid var(--border-strong)", color: "var(--text)" }}
            >
              {index + 1}
            </span>
            <span className="flex min-w-0 flex-col">
              <b className="text-sm" style={{ color: "var(--text)" }}>{t(`steps.${step}.title`)}</b>
              <span className="text-sm" style={{ color: "var(--muted)" }}>{t(`steps.${step}.body`)}</span>
            </span>
          </li>
        ))}
      </ol>
      <div className="flex flex-wrap gap-2">
        <Link href={adminHref("/admin/shop/products/new", organizationSlug)} className={primaryButtonClass} style={primaryButtonStyle}>
          + {t("addProduct")}
        </Link>
        <Link href={adminHref("/admin/settings/locations", organizationSlug)} className={`${secondaryButtonClass} inline-flex items-center`} style={secondaryButtonStyle}>
          {t("pickupSettings")}
        </Link>
      </div>
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("membersNote")}</p>
    </section>
  );
}
