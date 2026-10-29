"use client";

import { useQuery } from "@tanstack/react-query";
import { useState, type FormEvent } from "react";
import { useTranslations } from "next-intl";

import { requestSignatures, type DocumentTemplate, type RequestInput, type RequestResult } from "@/api/documents";
import { fetchFinancePackages } from "@/api/finance";
import { Segmented } from "@/components/admin/finance/packages/package-ui";
import { primaryButtonClass, primaryButtonStyle } from "@/components/staff/staff-ui";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { useUiTranslations } from "@/i18n/ui";

import { documentError } from "../document-errors";
import { useToken } from "../use-documents";
import { Hint } from "./staff-parts";

type Audience = "all_clients" | "role" | "package";

/**
 * «Αίτημα υπογραφής» in bulk (ADR-252 §2): every client, a role (μέλη box
 * or αθλητές) or the holders of a subscription package. One client is asked
 * from their row in the panel or from their profile. Clients who already
 * signed, or already have a request, are skipped.
 */
export function RequestDialog({
  template,
  onClose,
  onSent,
}: {
  template: DocumentTemplate;
  onClose: () => void;
  onSent: (result: RequestResult) => void;
}) {
  const t = useTranslations("Documents");
  const i18n = useUiTranslations();
  const token = useToken();
  const [audience, setAudience] = useState<Audience>("all_clients");
  const [role, setRole] = useState<"member" | "athlete">("member");
  const [packageId, setPackageId] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const packages = useQuery({
    queryKey: ["documents", "request-packages"],
    enabled: Boolean(token && audience === "package"),
    queryFn: () => fetchFinancePackages(token!),
  });
  const packageOptions = (packages.data?.packages ?? [])
    .map((record) => ({ id: String(record.id ?? ""), name: String(record.name ?? "") }))
    .filter((record) => record.id && record.name);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!token) return;
    if (audience === "package" && !packageId) {
      setError(t("errorPackageRequired"));
      return;
    }
    const input: RequestInput =
      audience === "all_clients" ? { audience } : audience === "role" ? { audience, role } : { audience, package_id: packageId };
    setBusy(true);
    setError(null);
    try {
      onSent(await requestSignatures(token, template.id, input));
    } catch (err) {
      setError(documentError(err, t, i18n).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog
      onClose={onClose}
      title={t("requestTitle")}
      eyebrow={template.title}
      size="md"
      variant="sheet"
      testId="request-dialog"
      dismissible={!busy}
      onSubmit={(event) => void submit(event)}
      error={error ? <ErrorNotice>{error}</ErrorNotice> : null}
      footer={
        <button type="submit" disabled={busy} className={primaryButtonClass} style={primaryButtonStyle}>
          {busy ? t("sending") : t("send")}
        </button>
      }
    >
      <div className="flex flex-col gap-3">
        <Segmented
          label={t("audienceLabel")}
          value={audience}
          onChange={(value) => {
            setAudience(value);
            setError(null);
          }}
          options={[
            { value: "all_clients", label: t("audienceAll") },
            { value: "role", label: t("audienceRole") },
            { value: "package", label: t("audiencePackage") },
          ]}
        />
        {audience === "role" ? (
          <Select value={role} onValueChange={(value) => setRole(value as "member" | "athlete")} aria-label={t("audienceRole")}>
            <option value="member">{t("roleMember")}</option>
            <option value="athlete">{t("roleAthlete")}</option>
          </Select>
        ) : null}
        {audience === "package" ? (
          <Select
            value={packageId}
            placeholder={t("choosePackage")}
            onValueChange={(value) => {
              setPackageId(value);
              setError(null);
            }}
            aria-label={t("audiencePackage")}
          >
            {packageOptions.map((option) => (
              <option key={option.id} value={option.id}>
                {option.name}
              </option>
            ))}
          </Select>
        ) : null}
        <Hint>{t("requestHint")}</Hint>
      </div>
    </Dialog>
  );
}
