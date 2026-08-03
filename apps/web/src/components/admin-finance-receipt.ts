import type { FinanceRecord } from "@/api/finance";

export type FinanceReceiptForm = {
  amount: string;
  paymentMethod: string;
  paidOn: string;
  description: string;
  notes: string;
  packageSubscriptionId: string;
};

export function buildFinanceReceiptPayload(
  form: FinanceReceiptForm,
  idempotencyKey: string,
): FinanceRecord {
  return {
    amount_cents: Math.round(Number(form.amount || 0) * 100),
    payment_method: form.paymentMethod,
    paid_on: form.paidOn || null,
    description: form.description,
    notes: form.notes || null,
    ...(form.packageSubscriptionId
      ? { membership_package_subscription_id: form.packageSubscriptionId }
      : {}),
    idempotency_key: idempotencyKey,
  };
}

export function receiptPackageLabel(
  receipt: Partial<
    Pick<FinanceRecord, "package_name" | "package_code_snapshot" | "package_family_snapshot">
  >,
) {
  return String(
    receipt.package_name ??
      receipt.package_code_snapshot ??
      receipt.package_family_snapshot ??
      "",
  );
}
