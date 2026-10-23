"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { INTEREST_LEVELS, fetchMyInterests, saveMyInterests, type InterestLevel } from "@/api/interests";
import { completeProductTour } from "@/api/onboarding";
import { redeemInvitation } from "@/api/organizations";
import { getAvatarUploadUrl, updateAvatar } from "@/api/profile";
import { getBoxVocabulary } from "@/api/public-profile";
import { AreaPicker } from "@/components/around/AreaPicker";
import { useAroundArea } from "@/components/around/use-around";
import { ChoiceChips } from "@/components/filters/FilterPage";
import { useSession } from "@/components/session-provider";
import { FIRST_RUN, markFirstRunDone, safeNext } from "@/lib/first-run";
import { useOrganizationMemberships } from "@/lib/membership-role";

const STEPS = ["photo", "interests", "where"] as const;
type Step = (typeof STEPS)[number];

/**
 * The member first-run after sign-up (ADR-183): photo, what you do, where
 * you are and whether you are in a box already. Every step can be skipped;
 * finishing or skipping records it on the account, so it shows once.
 */
export function FirstRun() {
  const t = useTranslations("FirstRun");
  const router = useRouter();
  const searchParams = useSearchParams();
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token ?? null;
  const [step, setStep] = useState<Step>("photo");
  const index = STEPS.indexOf(step);

  function finish() {
    if (currentUser) markFirstRunDone(currentUser.id);
    if (token) void completeProductTour(token, FIRST_RUN).catch(() => undefined);
    router.replace(safeNext(searchParams.get("next")));
  }

  const next = () => (index < STEPS.length - 1 ? setStep(STEPS[index + 1]) : finish());

  return (
    <main className="flex min-h-screen justify-center px-4 py-8" style={{ background: "var(--bg)" }}>
      <div className="flex w-full max-w-md flex-col gap-6">
        <div className="flex items-center justify-between gap-3">
          <ol aria-label={t("progress", { step: index + 1, total: STEPS.length })} className="flex gap-1.5">
            {STEPS.map((entry, position) => (
              <li
                key={entry}
                aria-current={entry === step ? "step" : undefined}
                className="h-1.5 w-8 rounded-full"
                style={{ background: position <= index ? "var(--primary)" : "var(--border-strong)" }}
              />
            ))}
          </ol>
          <button
            type="button"
            onClick={finish}
            className="min-h-11 px-2 text-sm font-semibold"
            style={{ color: "var(--text-soft)" }}
          >
            {t("skipAll")}
          </button>
        </div>

        {step === "photo" ? <PhotoStep onNext={next} /> : null}
        {step === "interests" ? <InterestsStep onNext={next} /> : null}
        {step === "where" ? <WhereStep onFinish={finish} /> : null}
      </div>
    </main>
  );
}

function StepHeading({ title, lead }: { title: string; lead: string }) {
  return (
    <header className="flex flex-col gap-1">
      <h1 className="text-2xl font-bold tracking-tight" style={{ color: "var(--text)" }}>{title}</h1>
      <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }}>{lead}</p>
    </header>
  );
}

function StepActions({
  primary,
  onPrimary,
  onSkip,
  busy,
}: {
  primary: string;
  onPrimary: () => void;
  onSkip?: () => void;
  busy?: boolean;
}) {
  const t = useTranslations("FirstRun");
  return (
    <div className="flex flex-col gap-2">
      <button
        type="button"
        onClick={onPrimary}
        disabled={busy}
        className="min-h-12 w-full rounded-2xl px-4 text-sm font-bold disabled:opacity-60"
        style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
      >
        {primary}
      </button>
      {onSkip ? (
        <button
          type="button"
          onClick={onSkip}
          className="min-h-11 w-full rounded-2xl px-4 text-sm font-semibold"
          style={{ color: "var(--text-soft)" }}
        >
          {t("skipStep")}
        </button>
      ) : null}
    </div>
  );
}

function ErrorText({ message }: { message: string }) {
  return (
    <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>
      {message}
    </p>
  );
}

function PhotoStep({ onNext }: { onNext: () => void }) {
  const t = useTranslations("FirstRun");
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token ?? null;
  const input = useRef<HTMLInputElement>(null);
  const [preview, setPreview] = useState<string | null>(currentUser?.avatar_url ?? null);
  const upload = useMutation({
    mutationFn: async (file: File) => {
      const { upload_url, key, required_headers } = await getAvatarUploadUrl(token!, file);
      const put = await fetch(upload_url, { method: "PUT", body: file, headers: required_headers });
      if (!put.ok) throw new Error("upload_failed");
      await updateAvatar(token!, key);
    },
  });

  function choose(file: File | undefined) {
    if (!file || !token) return;
    setPreview(URL.createObjectURL(file));
    upload.mutate(file);
  }

  return (
    <section className="flex flex-col gap-6">
      <StepHeading title={t("photoTitle")} lead={t("photoLead")} />
      <div className="flex flex-col items-center gap-3">
        <button
          type="button"
          onClick={() => input.current?.click()}
          aria-label={preview ? t("photoChange") : t("photoAdd")}
          className="grid h-28 w-28 place-items-center overflow-hidden rounded-full"
          style={{ background: "var(--panel-raised)", border: "2px dashed var(--border-strong)" }}
        >
          {preview ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={preview} alt="" className="h-full w-full object-cover" />
          ) : (
            <span aria-hidden="true" className="text-3xl" style={{ color: "var(--dim)" }}>+</span>
          )}
        </button>
        <p className="text-lg font-semibold" style={{ color: "var(--text)" }}>{currentUser?.nickname}</p>
        <input
          ref={input}
          type="file"
          accept="image/*"
          className="hidden"
          onChange={(event) => choose(event.target.files?.[0])}
        />
        {upload.isError ? <ErrorText message={t("photoFailed")} /> : null}
      </div>
      <StepActions
        primary={preview ? t("continue") : t("photoAdd")}
        onPrimary={() => (preview ? onNext() : input.current?.click())}
        onSkip={preview ? undefined : onNext}
        busy={upload.isPending}
      />
    </section>
  );
}

function InterestsStep({ onNext }: { onNext: () => void }) {
  const t = useTranslations("FirstRun");
  const tags = useTranslations("BoxTags");
  const partners = useTranslations("Partners");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const vocabulary = useQuery({ queryKey: ["box-vocabulary"], queryFn: getBoxVocabulary, staleTime: Infinity });
  const saved = useQuery({
    queryKey: ["my-interests"],
    enabled: Boolean(token),
    queryFn: () => fetchMyInterests(token!),
  });
  const [disciplines, setDisciplines] = useState<string[] | null>(null);
  const [level, setLevel] = useState<InterestLevel | null | undefined>(undefined);
  const picked = disciplines ?? saved.data?.disciplines ?? [];
  const pickedLevel = level === undefined ? (saved.data?.level ?? null) : level;
  const save = useMutation({
    mutationFn: () => saveMyInterests(token!, { disciplines: picked, level: pickedLevel }),
    onSuccess: (interests) => {
      queryClient.setQueryData(["my-interests"], interests);
      onNext();
    },
  });
  const nothing = picked.length === 0 && pickedLevel === null;

  return (
    <section className="flex flex-col gap-6">
      <StepHeading title={t("interestsTitle")} lead={t("interestsLead")} />
      {(vocabulary.data?.discipline_groups ?? []).map((group) => (
        <div key={group.key} className="flex flex-col gap-2">
          <h2 className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {tags(["group", group.key].join("."))}
          </h2>
          <ChoiceChips
            ariaLabel={tags(["group", group.key].join("."))}
            multiple
            options={group.items.map((key) => ({ value: key, label: tags(["discipline", key].join(".")) }))}
            selected={picked.filter((key) => group.items.includes(key))}
            onChange={(values) =>
              setDisciplines([...picked.filter((key) => !group.items.includes(key)), ...values].slice(0, 12))
            }
          />
        </div>
      ))}
      {vocabulary.isError ? <ErrorText message={t("loadFailed")} /> : null}
      <div className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("levelTitle")}</h2>
        <ChoiceChips
          ariaLabel={t("levelTitle")}
          multiple={false}
          options={INTEREST_LEVELS.map((value) => ({ value, label: partners(`level_${value}`) }))}
          selected={pickedLevel ? [pickedLevel] : []}
          onChange={(values) => setLevel(values[0] ?? null)}
        />
      </div>
      {save.isError ? <ErrorText message={t("saveFailed")} /> : null}
      <StepActions
        primary={t("continue")}
        onPrimary={() => (nothing || !token ? onNext() : save.mutate())}
        onSkip={onNext}
        busy={save.isPending}
      />
    </section>
  );
}

function WhereStep({ onFinish }: { onFinish: () => void }) {
  const t = useTranslations("FirstRun");
  const area = useAroundArea();
  const [areaSaved, setAreaSaved] = useState(false);

  return (
    <section className="flex flex-col gap-6">
      <StepHeading title={t("whereTitle")} lead={t("whereLead")} />
      {area.isSuccess ? (
        <AreaPicker initial={area.data} submitLabel={t("areaSave")} onSaved={() => setAreaSaved(true)} />
      ) : null}
      {areaSaved ? (
        <p role="status" className="text-sm font-semibold" style={{ color: "var(--success)" }}>{t("areaSaved")}</p>
      ) : null}
      <BoxQuestion />
      <StepActions primary={t("finish")} onPrimary={onFinish} />
    </section>
  );
}

function BoxQuestion() {
  const t = useTranslations("FirstRun");
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const memberships = useOrganizationMemberships();
  const [mode, setMode] = useState<"ask" | "code" | "later">("ask");
  const [code, setCode] = useState("");
  const redeem = useMutation({
    mutationFn: () => redeemInvitation(token!, code.trim()),
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: ["organization-memberships", currentUser?.id ?? null] }),
  });
  const boxes = memberships.data ?? [];

  if (boxes.length > 0) {
    return (
      <div className="rounded-2xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
          {t("alreadyIn", { name: boxes[0].organization.name })}
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-3 rounded-2xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <h2 className="text-base font-bold" style={{ color: "var(--text)" }}>{t("boxQuestion")}</h2>
      {mode === "code" ? (
        <form
          className="flex flex-col gap-2"
          onSubmit={(event) => {
            event.preventDefault();
            if (code.trim().length >= 20 && token) redeem.mutate();
          }}
        >
          <label className="text-sm font-semibold" style={{ color: "var(--text-soft)" }} htmlFor="first-run-code">
            {t("codeLabel")}
          </label>
          <input
            id="first-run-code"
            value={code}
            onChange={(event) => setCode(event.target.value)}
            autoComplete="off"
            className="min-h-11 w-full rounded-2xl px-3 text-sm"
            style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
          />
          {redeem.isError ? <ErrorText message={t("codeFailed")} /> : null}
          <button
            type="submit"
            disabled={redeem.isPending || code.trim().length < 20}
            className="min-h-11 rounded-2xl px-4 text-sm font-bold disabled:opacity-60"
            style={{ background: "var(--panel-raised)", border: "1px solid var(--border-strong)", color: "var(--text)" }}
          >
            {t("codeSubmit")}
          </button>
        </form>
      ) : mode === "later" ? (
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("laterNote")}</p>
      ) : (
        <div className="flex flex-col gap-2">
          <Link
            href="/around/boxes"
            className="flex min-h-11 items-center rounded-2xl px-3 text-sm font-semibold"
            style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
          >
            {t("findBox")}
          </Link>
          <button
            type="button"
            onClick={() => setMode("code")}
            className="flex min-h-11 items-center rounded-2xl px-3 text-left text-sm font-semibold"
            style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
          >
            {t("haveCode")}
          </button>
          <button
            type="button"
            onClick={() => setMode("later")}
            className="flex min-h-11 items-center rounded-2xl px-3 text-left text-sm font-semibold"
            style={{ color: "var(--text-soft)" }}
          >
            {t("notYet")}
          </button>
        </div>
      )}
    </div>
  );
}
