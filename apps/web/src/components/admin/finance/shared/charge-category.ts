export const CHARGE_CATEGORIES = ["product", "personal_training", "event", "other"] as const;

export type ChargeCategory = (typeof CHARGE_CATEGORIES)[number];

export const CHARGE_CATEGORY_LABEL_KEYS: Record<ChargeCategory, string> = {
  product: "admChargeCategoryProduct",
  personal_training: "admChargeCategoryPersonalTraining",
  event: "admChargeCategoryEvent",
  other: "admChargeCategoryOther",
};

export function isChargeCategory(value: string): value is ChargeCategory {
  return (CHARGE_CATEGORIES as readonly string[]).includes(value);
}

/**
 * Body for a manual invoice. A categorised manual charge is sent as an explicit
 * line so the member discount can apply to it (ADR-097); the plain amount form
 * carries no category. Package invoices keep the amount form, which the API
 * prefills from the subscription.
 */
export function manualInvoiceBody(form: {
  amountCents: number;
  description: string;
  dueDate: string;
  subscriptionId: string;
  chargeCategory: string;
  /** Line text when the admin left the description empty, e.g. the category name. */
  fallbackDescription: string;
}) {
  const base = { due_date: form.dueDate || undefined };
  if (!form.subscriptionId && isChargeCategory(form.chargeCategory)) {
    const description = form.description.trim() || form.fallbackDescription;
    return {
      ...base,
      description,
      lines: [
        {
          line_type: "manual_charge",
          charge_category: form.chargeCategory,
          description,
          quantity: 1,
          unit_amount_cents: form.amountCents,
        },
      ],
    };
  }
  return {
    ...base,
    amount_cents: form.amountCents,
    description: form.description || undefined,
    membership_package_subscription_id: form.subscriptionId || undefined,
  };
}
