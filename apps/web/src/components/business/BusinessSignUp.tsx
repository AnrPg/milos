"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import { signUpBusiness, type BusinessKind } from "@/api/business-accounts";
import { AgeConfirmationField } from "@/components/auth/AgeConfirmationField";
import { AuthField } from "@/components/auth/AuthField";
import { AuthNotice, AuthShell, primaryButtonClass, primaryButtonStyle } from "@/components/auth/AuthShell";
import { CheckInboxNotice } from "@/components/auth/CheckInboxNotice";
import { RecoveryCodesOffer } from "@/components/auth/RecoveryCodesOffer";
import { SignupHandleField, useHandleSuggestion } from "@/components/auth/SignupHandleField";
import { MIN_PASSWORD_LENGTH, registerFailure, type FieldErrors } from "@/components/auth/auth-errors";
import { BusinessKindPicker } from "@/components/business/BusinessKindPicker";
import { useSession } from "@/components/session-provider";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { rememberSelectedOrganization } from "@/lib/organization-slug";
import { setView } from "@/lib/view-mode";

/**
 * ADR-184: where the register form's «Επαγγελματικός λογαριασμός» link
 * points. Kept as a named export so the sign-up console can link to it
 * without knowing the route.
 */
export const BUSINESS_SIGN_UP_HREF = "/register/business";

/** The quiet link to the business sign-up, for the register form. */
export function BusinessSignUpLink({ className = "" }: { className?: string }) {
  const t = useTranslations("Business");
  return (
    <Link href={BUSINESS_SIGN_UP_HREF} className={`text-sm font-semibold ${className}`} style={{ color: "var(--dim)" }}>
      {t("signUp.link")}
    </Link>
  );
}

type AccountForm = { display_name: string; handle: string; email: string; password: string; age_confirmed: boolean };
type BusinessForm = { business_kind: BusinessKind; business_name: string; city: string; phone: string };

const MAX_DISPLAY_NAME_LENGTH = 50;

/**
 * ADR-184: the business sign-up. A new account (or one that registered a
 * moment ago) opens a gym or an independent coach's practice in demo mode:
 * everything works with demo data, nothing goes live until the Palee team
 * activates it. Older accounts ask from Εγώ › Ρυθμίσεις instead.
 */
export function BusinessSignUp() {
  const t = useTranslations("Business");
  const tAuth = useTranslations("authRecovery");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const router = useRouter();
  const queryClient = useQueryClient();
  const { status, tokens, signUp } = useSession();
  const [account, setAccount] = useState<AccountForm>({
    display_name: "",
    handle: "",
    email: "",
    password: "",
    age_confirmed: false,
  });
  const [business, setBusiness] = useState<BusinessForm>({ business_kind: "gym", business_name: "", city: "", phone: "" });
  const [handleEdited, setHandleEdited] = useState(false);
  const [fieldErrors, setFieldErrors] = useState<FieldErrors>({});
  const [error, setError] = useState<string | null>(null);
  const [closed, setClosed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [created, setCreated] = useState<string | null>(null);
  const [registered, setRegistered] = useState(false);
  // ADR-211: the email already had an account; nothing was created.
  const [inboxEmail, setInboxEmail] = useState<string | null>(null);
  const pendingBusiness = useRef(false);
  const guest = status === "guest";

  const applySuggestedHandle = useCallback((handle: string) => setAccount((form) => ({ ...form, handle })), []);
  useHandleSuggestion(account.display_name, guest && !handleEdited, applySuggestedHandle);

  const openBusiness = useCallback(
    async (token: string) => {
      setBusy(true);
      setError(null);
      try {
        const organization = await signUpBusiness(token, {
          business_kind: business.business_kind,
          business_name: business.business_name.trim(),
          city: business.city.trim() || null,
          phone: business.phone.trim() || null,
          timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
          default_locale: locale,
        });
        rememberSelectedOrganization(organization.slug);
        setView("staff");
        queryClient.clear();
        setCreated(organization.slug);
      } catch (caught) {
        if (caught instanceof ApiError && caught.payload.code === "business_signup_closed") setClosed(true);
        else setError(localizeError(caught, i18n));
      } finally {
        setBusy(false);
      }
    },
    [business, i18n, locale, queryClient],
  );

  // The account is committed first; the business follows once its token is there.
  useEffect(() => {
    const token = tokens?.access_token;
    if (status !== "authenticated" || !token || !pendingBusiness.current) return;
    pendingBusiness.current = false;
    void openBusiness(token);
  }, [openBusiness, status, tokens]);

  function invalidFields(): FieldErrors {
    const errors: FieldErrors = {};
    if (business.business_name.trim().length < 2) errors.business_name = [t("signUp.nameRule")];
    if (!guest) return errors;
    const displayName = account.display_name.trim();
    if (displayName.length === 0 || displayName.length > MAX_DISPLAY_NAME_LENGTH) {
      errors.display_name = [tAuth("displayNameRule")];
    }
    if (account.handle.trim().length < 3) errors.handle = [tAuth("handleRule")];
    if (account.password.length < MIN_PASSWORD_LENGTH) errors.password = [tAuth("passwordRule")];
    if (!account.age_confirmed) errors.age_confirmed = [tAuth("minimumAgeRule")];
    return errors;
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    const errors = invalidFields();
    setFieldErrors(errors);
    if (Object.keys(errors).length > 0) return;

    if (!guest) {
      if (tokens?.access_token) await openBusiness(tokens.access_token);
      return;
    }

    setBusy(true);
    setError(null);
    try {
      pendingBusiness.current = true;
      setRegistered(true);
      const result = await signUp({
        handle: account.handle.trim(),
        display_name: account.display_name.trim(),
        email: account.email.trim(),
        password: account.password,
        age_confirmed: account.age_confirmed,
        role: "member",
      });
      if (!result.user) {
        pendingBusiness.current = false;
        setRegistered(false);
        setBusy(false);
        setInboxEmail(result.email);
      }
    } catch (caught) {
      pendingBusiness.current = false;
      setRegistered(false);
      setBusy(false);
      const failure = registerFailure(
        caught,
        tAuth,
        (failed) => localizeError(failed, i18n),
        i18n("apiValidationField"),
      );
      setError(failure.message);
      setFieldErrors(failure.fieldErrors);
    }
  }

  const goToConsole = () => router.replace(created ? `/org/${created}/admin` : "/admin");

  if (created) {
    return (
      <AuthShell title={t("signUp.createdTitle")}>
        <div className="space-y-5">
          <AuthNotice tone="success">{t("signUp.created")}</AuthNotice>
          {registered ? (
            <RecoveryCodesOffer onSkip={goToConsole} />
          ) : (
            <button type="button" className={primaryButtonClass} style={primaryButtonStyle} onClick={goToConsole}>
              {t("signUp.openConsole")}
            </button>
          )}
        </div>
      </AuthShell>
    );
  }

  if (inboxEmail) {
    return (
      <AuthShell title={t("signUp.title")}>
        <CheckInboxNotice email={inboxEmail} onContinue={() => router.replace("/login")} />
      </AuthShell>
    );
  }

  if (closed) {
    return (
      <AuthShell title={t("signUp.title")}>
        <div className="space-y-5">
          <AuthNotice>{t("signUp.closed")}</AuthNotice>
          <Link href="/me/settings#business" className={`block text-center ${primaryButtonClass}`} style={primaryButtonStyle}>
            {t("signUp.closedAction")}
          </Link>
        </div>
      </AuthShell>
    );
  }

  return (
    <AuthShell title={t("signUp.title")}>
      <form className="space-y-5" onSubmit={submit} noValidate>
        <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }}>{t("signUp.intro")}</p>

        <BusinessKindPicker value={business.business_kind} onChange={(business_kind) => setBusiness((form) => ({ ...form, business_kind }))} />

        <AuthField
          label={t(business.business_kind === "coach" ? "form.coachName" : "form.gymName")}
          value={business.business_name}
          maxLength={120}
          errors={fieldErrors.business_name}
          onChange={(business_name) => setBusiness((form) => ({ ...form, business_name }))}
        />
        <AuthField
          label={t("form.city")}
          value={business.city}
          maxLength={80}
          autoComplete="address-level2"
          onChange={(city) => setBusiness((form) => ({ ...form, city }))}
        />
        <AuthField
          label={t("form.phone")}
          value={business.phone}
          maxLength={40}
          autoComplete="tel"
          hint={t("form.phoneHint")}
          onChange={(phone) => setBusiness((form) => ({ ...form, phone }))}
        />

        {guest ? (
          <fieldset className="space-y-5 border-t pt-5" style={{ borderColor: "var(--border)" }}>
            <legend className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>
              {t("signUp.account")}
            </legend>
            <AuthField
              label={tAuth("displayNameLabel")}
              value={account.display_name}
              autoComplete="name"
              placeholder={tAuth("displayNamePlaceholder")}
              hint={tAuth("displayNameHint")}
              maxLength={MAX_DISPLAY_NAME_LENGTH}
              errors={fieldErrors.display_name}
              onChange={(display_name) => setAccount((form) => ({ ...form, display_name }))}
            />
            <SignupHandleField
              value={account.handle}
              errors={fieldErrors.handle}
              onChange={(handle) => {
                setHandleEdited(handle.length > 0);
                setAccount((form) => ({ ...form, handle }));
              }}
            />
            <AuthField
              label={i18n("emailAddress")}
              value={account.email}
              type="email"
              inputMode="email"
              autoComplete="email"
              placeholder={i18n("emailAddressPlaceholder")}
              hint={tAuth("emailNotice")}
              errors={fieldErrors.email}
              onChange={(email) => setAccount((form) => ({ ...form, email }))}
            />
            <AuthField
              label={i18n("password8be3c94")}
              value={account.password}
              type="password"
              autoComplete="new-password"
              placeholder={tAuth("passwordRule")}
              errors={fieldErrors.password}
              onChange={(password) => setAccount((form) => ({ ...form, password }))}
            />
            <AgeConfirmationField
              checked={account.age_confirmed}
              errors={fieldErrors.age_confirmed}
              onChange={(age_confirmed) => setAccount((form) => ({ ...form, age_confirmed }))}
            />
          </fieldset>
        ) : null}

        <div
          className="rounded-2xl px-4 py-3 text-sm leading-6"
          style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
        >
          {t("signUp.demoNote")}
        </div>

        {error ? <AuthNotice>{error}</AuthNotice> : null}

        <button type="submit" className={primaryButtonClass} style={primaryButtonStyle} disabled={busy || status === "loading"}>
          {busy ? t("signUp.creating") : t("signUp.submit")}
        </button>

        <p className="text-center text-sm" style={{ color: "var(--text-soft)" }}>
          <Link href="/register" className="font-semibold" style={{ color: "var(--primary)" }}>
            {t("signUp.personal")}
          </Link>
        </p>
      </form>
    </AuthShell>
  );
}
