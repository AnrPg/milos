"use client";

import { useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { SESSION_UPDATED_EVENT } from "@/api/client";
import { fetchMyReviews } from "@/api/reviews";
import { getAvatarUploadUrl, updateProfile } from "@/api/profile";
import { fetchGamificationPreferences, updateGamificationPreferences } from "@/api/gamification";
import { ReviewList } from "@/components/my-reviews";
import { useSession } from "@/components/session-provider";
import { TransientHero } from "@/components/TransientHero";

const DAY_LABELS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"] as const;

function CollapsibleSection({
  id,
  title,
  description,
  defaultOpen = false,
  children,
}: {
  id: string;
  title: string;
  description?: string;
  defaultOpen?: boolean;
  children: React.ReactNode;
}) {
  const [open, setOpen] = useState(defaultOpen);

  return (
    <section
      id={id}
      className="overflow-hidden rounded-[2.4rem]"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <button
        className="flex w-full items-center justify-between gap-4 p-8 text-left"
        type="button"
        onClick={() => setOpen((v) => !v)}
      >
        <div>
          <p
            className="text-sm font-semibold uppercase tracking-[0.24em]"
            style={{ color: "var(--primary)" }}
          >
            {title}
          </p>
          {description && (
            <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>
              {description}
            </p>
          )}
        </div>
        <span className="text-xl font-light" style={{ color: "var(--dim)" }}>
          {open ? "−" : "+"}
        </span>
      </button>
      {open && (
        <div className="border-t px-8 pb-8 pt-6" style={{ borderColor: "var(--border)" }}>
          {children}
        </div>
      )}
    </section>
  );
}

function FieldGroup({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <label className="block text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--muted)" }}>
        {label}
      </label>
      {children}
    </div>
  );
}

function TextInput(props: React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      {...props}
      className="w-full rounded-xl px-4 py-2.5 text-sm outline-none"
      style={{
        background: "var(--panel-muted)",
        border: "1px solid var(--border)",
        color: "var(--text)",
      }}
    />
  );
}

type CurrentUserWithAvatar = {
  id: string;
  nickname: string;
  role: string;
  avatar_url?: string | null;
};

export function ProfilePage() {
  const { tokens, currentUser } = useSession();
  const user = currentUser as CurrentUserWithAvatar | null;

  const [nicknameValue, setNicknameValue] = useState(user?.nickname ?? "");
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [personalError, setPersonalError] = useState<string | null>(null);
  const [personalSuccess, setPersonalSuccess] = useState<string | null>(null);
  const [personalPending, setPersonalPending] = useState(false);

  const [avatarPending, setAvatarPending] = useState(false);
  const [avatarError, setAvatarError] = useState<string | null>(null);
  const [avatarPreview, setAvatarPreview] = useState<string | null>(user?.avatar_url ?? null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const queryClient = useQueryClient();

  const reviewsQuery = useQuery({
    queryKey: ["my", "reviews"],
    enabled: Boolean(tokens?.access_token),
    queryFn: async () => fetchMyReviews(tokens!.access_token),
  });

  const prefsQuery = useQuery({
    queryKey: ["gamification", "preferences"],
    enabled: Boolean(tokens?.access_token),
    queryFn: async () => fetchGamificationPreferences(tokens!.access_token),
  });

  const [offDaysDraft, setOffDaysDraft] = useState<number[] | null>(null);
  const offDays = offDaysDraft ?? prefsQuery.data?.off_days ?? [];

  const updatePrefsMutation = useMutation({
    mutationFn: async (days: number[]) => {
      if (!tokens) throw new Error("Not authenticated");
      return updateGamificationPreferences(tokens.access_token, { off_days: days });
    },
    onSuccess: (data) => {
      void queryClient.invalidateQueries({ queryKey: ["gamification", "preferences"] });
      void queryClient.invalidateQueries({ queryKey: ["landing"] });
      setOffDaysDraft(data.off_days);
    },
  });

  function toggleOffDay(dow: number) {
    const current = offDays;
    const next = current.includes(dow)
      ? current.filter((d) => d !== dow)
      : current.length >= 3
        ? current
        : [...current, dow];
    setOffDaysDraft(next);
    updatePrefsMutation.mutate(next);
  }

  function broadcastUserUpdate(updatedUser: CurrentUserWithAvatar) {
    if (!tokens) return;
    window.dispatchEvent(
      new CustomEvent(SESSION_UPDATED_EVENT, {
        detail: {
          tokens,
          currentUser: { ...currentUser, ...updatedUser },
        },
      }),
    );
  }

  async function handlePersonalSave(e: React.FormEvent) {
    e.preventDefault();
    if (!tokens) return;

    setPersonalError(null);
    setPersonalSuccess(null);
    setPersonalPending(true);

    try {
      const payload: Record<string, string> = {};
      if (nicknameValue.trim() && nicknameValue.trim() !== user?.nickname) {
        payload.nickname = nicknameValue.trim();
      }
      if (newPassword) {
        payload.current_password = currentPassword;
        payload.password = newPassword;
      }

      if (Object.keys(payload).length === 0) {
        setPersonalSuccess("Nothing to update.");
        return;
      }

      const result = await updateProfile(tokens.access_token, payload);
      broadcastUserUpdate(result.user);
      setNicknameValue(result.user.nickname);
      setCurrentPassword("");
      setNewPassword("");
      setPersonalSuccess("Profile updated.");
    } catch (err) {
      setPersonalError(err instanceof Error ? err.message : "Update failed.");
    } finally {
      setPersonalPending(false);
    }
  }

  async function handleAvatarFile(file: File) {
    if (!tokens) return;
    setAvatarError(null);
    setAvatarPending(true);

    try {
      const { upload_url, public_url } = await getAvatarUploadUrl(tokens.access_token);

      const uploadRes = await fetch(upload_url, {
        method: "PUT",
        body: file,
        headers: { "Content-Type": file.type || "image/jpeg" },
      });

      if (!uploadRes.ok) throw new Error("Upload to storage failed.");

      const result = await updateProfile(tokens.access_token, { avatar_url: public_url });
      broadcastUserUpdate(result.user);
      setAvatarPreview(public_url);
    } catch (err) {
      setAvatarError(err instanceof Error ? err.message : "Avatar upload failed.");
    } finally {
      setAvatarPending(false);
    }
  }

  return (
    <main className="min-h-screen px-6 py-10 md:px-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-3xl space-y-4">
        <TransientHero label="profile introduction">
        <div className="mb-4">
          <p className="text-xs font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>
            Profile
          </p>
          <h1 className="mt-1 text-3xl font-black" style={{ color: "var(--text)" }}>
            Your account
          </h1>
        </div>
        </TransientHero>

        <CollapsibleSection
          id="personal"
          title="Personal Info"
          description="Nickname and password"
          defaultOpen
        >
          <form className="space-y-5" onSubmit={(e) => void handlePersonalSave(e)}>
            <FieldGroup label="Nickname">
              <TextInput
                value={nicknameValue}
                onChange={(e) => setNicknameValue(e.target.value)}
                placeholder="Your nickname"
                minLength={3}
                maxLength={30}
                pattern="[a-zA-Z0-9_]+"
              />
            </FieldGroup>

            <div className="border-t pt-5" style={{ borderColor: "var(--border)" }}>
              <p className="text-xs font-semibold uppercase tracking-[0.18em] mb-4" style={{ color: "var(--muted)" }}>
                Change password (leave blank to keep current)
              </p>
              <div className="space-y-3">
                <FieldGroup label="Current password">
                  <TextInput
                    type="password"
                    value={currentPassword}
                    onChange={(e) => setCurrentPassword(e.target.value)}
                    placeholder="Enter current password"
                    autoComplete="current-password"
                  />
                </FieldGroup>
                <FieldGroup label="New password">
                  <TextInput
                    type="password"
                    value={newPassword}
                    onChange={(e) => setNewPassword(e.target.value)}
                    placeholder="At least 8 characters"
                    minLength={8}
                    autoComplete="new-password"
                  />
                </FieldGroup>
              </div>
            </div>

            {personalError && (
              <p className="text-sm font-semibold" style={{ color: "var(--danger)" }}>
                {personalError}
              </p>
            )}
            {personalSuccess && (
              <p className="text-sm font-semibold" style={{ color: "var(--primary)" }}>
                {personalSuccess}
              </p>
            )}

            <button
              type="submit"
              disabled={personalPending}
              className="rounded-xl px-6 py-2.5 text-sm font-semibold disabled:opacity-50"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            >
              {personalPending ? "Saving…" : "Save changes"}
            </button>
          </form>
        </CollapsibleSection>

        <CollapsibleSection
          id="training-schedule"
          title="Training Schedule"
          description="Mark your weekly rest days (up to 3)"
        >
          <div className="space-y-5">
            <p className="text-sm" style={{ color: "var(--muted)" }}>
              Off-days are transparent to your streak — missing a scheduled rest day won&apos;t break it.
            </p>
            <div className="flex flex-wrap gap-2">
              {DAY_LABELS.map((label, dow) => {
                const selected = offDays.includes(dow);
                const disabled = !selected && offDays.length >= 3;
                return (
                  <button
                    key={dow}
                    type="button"
                    disabled={disabled || updatePrefsMutation.isPending}
                    onClick={() => toggleOffDay(dow)}
                    className="rounded-xl px-4 py-2 text-sm font-semibold transition-opacity disabled:opacity-40"
                    style={{
                      background: selected ? "var(--primary)" : "var(--panel-muted)",
                      color: selected ? "var(--primary-contrast)" : "var(--text-soft)",
                      border: selected
                        ? "1px solid var(--primary)"
                        : "1px solid var(--border)",
                    }}
                  >
                    {label}
                  </button>
                );
              })}
            </div>
            {updatePrefsMutation.isError && (
              <p className="text-sm font-semibold" style={{ color: "var(--danger)" }}>
                Failed to save. Please try again.
              </p>
            )}
          </div>
        </CollapsibleSection>

        <CollapsibleSection id="avatar" title="Avatar" description="Profile picture">
          <div className="space-y-5">
            {avatarPreview && (
              <div className="flex items-center gap-4">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={avatarPreview}
                  alt="Avatar preview"
                  className="h-20 w-20 rounded-full object-cover"
                  style={{ border: "2px solid var(--border)" }}
                />
                <p className="text-sm" style={{ color: "var(--muted)" }}>
                  Current avatar
                </p>
              </div>
            )}

            <input
              ref={fileInputRef}
              type="file"
              accept="image/*"
              className="hidden"
              onChange={(e) => {
                const file = e.target.files?.[0];
                if (file) void handleAvatarFile(file);
              }}
            />

            <button
              type="button"
              disabled={avatarPending}
              onClick={() => fileInputRef.current?.click()}
              className="rounded-xl px-6 py-2.5 text-sm font-semibold disabled:opacity-50"
              style={{
                background: "var(--panel-muted)",
                border: "1px solid var(--border)",
                color: "var(--text)",
              }}
            >
              {avatarPending ? "Uploading…" : avatarPreview ? "Change avatar" : "Upload avatar"}
            </button>

            {avatarError && (
              <p className="text-sm font-semibold" style={{ color: "var(--danger)" }}>
                {avatarError}
              </p>
            )}
          </div>
        </CollapsibleSection>

        <CollapsibleSection
          id="account-activity"
          title="Account Activity"
          description="Your reviews and history"
        >
          <div className="space-y-4">
            <p className="text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "var(--muted)" }}>
              My Reviews History
            </p>
            {reviewsQuery.isLoading ? (
              <p className="text-sm" style={{ color: "var(--dim)" }}>
                Loading reviews…
              </p>
            ) : (
              <ReviewList reviews={(reviewsQuery.data?.reviews ?? []) as Parameters<typeof ReviewList>[0]["reviews"]} />
            )}
          </div>
        </CollapsibleSection>
      </div>
    </main>
  );
}
