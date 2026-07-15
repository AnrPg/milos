# Plan: Profile Page + Messaging Improvements + Nav Refactor

**Status:** Ready to implement — all design decisions confirmed by user.  
**Working directory:** `/home/rodochrousbisbiki/MyApps/milos`  
**Elixir app:** `apps/api/` | **Next.js app:** `apps/web/`

---

## 1. Feature Summary (7 items)

| # | Feature | Status |
|---|---------|--------|
| 1 | Nav chat badge search: all users, recents first | Design approved |
| 2 | Thread list: show nickname instead of UUID | Design approved |
| 3 | Workout chat notifications → "Messages" filter | Already correct in frontend |
| 4 | Fix `push_message_builder` for `chat_message` type | Design approved |
| 5 | Remove Wellbeing from TopNav → "Training Readiness" side panel button (non-admin only) | Approved |
| 6 | Remove Reviews from TopNav → "Leave a Review" side panel button (non-admin only) | Approved |
| 7 | New `/profile` page (personal info, avatar, account activity) | Design approved |

---

## 2. Confirmed Design Decisions

### User-confirmed (explicit Q&A)

- **a) Password change** requires current password verification before allowing new password
- **b) Avatar bucket** is a SEPARATE MinIO bucket (`milos-avatars`), different from `milos-invoices`
- **c) Profile route** is `/profile` (not `/account/profile`)
- **d) Training Readiness + Leave a Review buttons** are for non-admin roles only (member/athlete)
- **e) Nickname propagation**: when nickname changes, ALL surfaces must update — including stored notification payloads

### Architecture decisions (derived from codebase analysis)

- `schema.ts` is GENERATED via `npm run generate:api` (Elixir OpenAPI → JSON → TypeScript). Never hand-edit it.
- Participant nicknames: batch-loaded at controller layer (not by changing Ecto schema), using `Identity.list_by_ids/1`
- `PropagateNicknameJob` Oban worker: needs `old_nickname` + `new_nickname` args to update notification payloads
- Notification historical payloads `sender_nickname`/`athlete_nickname`: user confirmed UPDATE ALL (not immutable)
- `milos-avatars` MinIO bucket must be created manually (public-read) in MinIO Console; only env var is added in code

---

## 3. Verified Nickname Propagation Scope

| Surface | Storage type | Propagation method |
|---------|-------------|-------------------|
| `weekly_leaderboard` MATERIALIZED VIEW | Stores `u.nickname` directly | `REFRESH MATERIALIZED VIEW CONCURRENTLY weekly_leaderboard` via `Gamification.refresh_leaderboard()` |
| Meilisearch member index | Stores nickname | `AdminMemberSearchDocuments.build_all()` + `AdminMemberSearchIndex.replace_documents(documents)` |
| `notifications` table payload JSONB | `sender_nickname`, `athlete_nickname` keys | SQL UPDATE via new `Notifications.propagate_nickname_change/2` |
| Finance invoices/referrals/coaching | `user_id` FK — live JOIN | Automatic, no action needed |
| `assignment_messages` | DROPPED (migration `20260614000004`) | No longer exists |

### PropagateNicknameJob design

```elixir
# apps/api/lib/milos_training/workers/propagate_nickname_job.ex
defmodule MilosTraining.Workers.PropagateNicknameJob do
  use Oban.Worker, queue: :default, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"old_nickname" => old_nickname, "new_nickname" => new_nickname}}) do
    # 1. Refresh weekly_leaderboard MV
    Gamification.refresh_leaderboard()
    # 2. Re-sync Meilisearch
    documents = AdminMemberSearchDocuments.build_all()
    AdminMemberSearchIndex.replace_documents(documents)
    # 3. Update notification payloads
    Notifications.propagate_nickname_change(old_nickname, new_nickname)
    :ok
  end
end
```

Enqueued from `UpdateProfile.call/2` when `old_nickname != new_nickname`:
```elixir
%{"old_nickname" => old_nickname, "new_nickname" => updated_user.nickname}
|> PropagateNicknameJob.new()
|> Oban.insert!()
```

### Notifications.propagate_nickname_change/2 design

New function in `Notifications` context → `NotificationStore` port → `EctoNotificationStore` implementation:

```elixir
# In EctoNotificationStore:
def propagate_nickname_change(old_nickname, new_nickname) do
  Repo.query!(
    "UPDATE notifications SET payload = jsonb_set(payload, '{sender_nickname}', to_jsonb($1::text)) WHERE payload->>'sender_nickname' = $2",
    [new_nickname, old_nickname]
  )
  Repo.query!(
    "UPDATE notifications SET payload = jsonb_set(payload, '{athlete_nickname}', to_jsonb($1::text)) WHERE payload->>'athlete_nickname' = $2",
    [new_nickname, old_nickname]
  )
  :ok
end
```

---

## 4. Key Implementation Patterns (from codebase)

### Elixir patterns
- All writes go through Ecto changesets. Hashing done in store (`maybe_put_password_hash`), not in changeset.
- `to_account/1` converts `User` schema → `Account` struct (done in `EctoUserStore`)
- `PasswordVerifier.verify/2` uses Argon2 — from `MilosTraining.Application.PasswordVerifier`
- Application services (`UpdateProfile`, etc.) take the current user `Account` struct as first arg (Guardian loads this fresh on every request — includes `password_hash`)
- Port callbacks in `identity/ports/user_store.ex` → dispatcher `identity/user_store.ex` → context `identity.ex`
- `RegistrationPolicy.normalize_nickname/1` = `String.trim/1 |> String.downcase/1`

### MinIO pattern (from `minio_storage.ex`)
```elixir
defp ex_aws_config do
  endpoint = Application.get_env(:milos_training, :minio_endpoint, "http://localhost:9000")
  access_key = Application.get_env(:milos_training, :minio_access_key, "minioadmin")
  secret_key = Application.get_env(:milos_training, :minio_secret_key, "minioadmin")
  bucket = Application.get_env(:milos_training, :minio_bucket, "milos-invoices")
  uri = URI.parse(endpoint)
  config = ExAws.Config.new(:s3, access_key_id: access_key, secret_access_key: secret_key,
    scheme: "#{uri.scheme}://", host: uri.host, port: uri.port, region: "us-east-1")
  {config, bucket}
end
```
Avatar variant uses `minio_avatar_bucket` config key (default `"milos-avatars"`).
Avatar public URL: `#{minio_public_endpoint}/milos-avatars/avatars/#{user_id}`
Avatar key: `"avatars/#{user_id}"` — fixed key (overwritten on re-upload, no cleanup needed).

### OpenAPI pattern
Controllers use `OpenApiSpex.ControllerSpecs` with `operation/2`. Export with `mix milos.export_openapi`.

### Frontend patterns
- `CurrentUser` type derived from `paths["/api/auth/me"]["get"]["responses"]["200"]["content"]["application/json"]` in `api/auth.ts`
- CSS theme vars: `--bg`, `--panel`, `--panel-muted`, `--border`, `--primary`, `--text`, `--muted`, `--dim`
- `queueMicrotask()` wraps setState calls inside `useEffect` (ESLint rule `react-hooks/set-state-in-effect`)
- Collapsible sections: see `admin-settings.tsx` for the existing pattern

---

## 5. Full Task Checklist

### Backend — New Files

- [ ] **`apps/api/priv/repo/migrations/20260615010000_add_avatar_url_to_users.exs`**  
  Add `avatar_url :string` column to `users` table

- [ ] **`apps/api/lib/milos_training/application/update_profile.ex`**  
  App service: verify current password if changing password, call `Identity.update_profile`, enqueue `PropagateNicknameJob` if nickname changed

- [ ] **`apps/api/lib/milos_training/application/update_avatar.ex`**  
  App service: calls `Identity.update_avatar(user.id, avatar_url)`

- [ ] **`apps/api/lib/milos_training/application/search_users.ex`**  
  App service: calls `Identity.search_users(query)`, returns list of `%{id, nickname, role}`

- [ ] **`apps/api/lib/milos_training/workers/propagate_nickname_job.ex`**  
  Oban worker: refresh leaderboard MV + Meilisearch re-sync + notification payload update

- [ ] **`apps/api/lib/milos_training_web/controllers/me_controller.ex`**  
  3 actions: `update_profile` (PATCH /api/me/profile), `avatar_upload_url` (POST /api/me/avatar/upload-url), `search_users` (GET /api/me/search/users)

### Backend — Modified Files

- [ ] **`apps/api/config/runtime.exs`**  
  Add: `minio_avatar_bucket: System.get_env("MINIO_AVATAR_BUCKET", "milos-avatars")`  
  Add: `minio_public_endpoint: System.get_env("MINIO_PUBLIC_ENDPOINT")` (optional, falls back to minio_endpoint)

- [ ] **`apps/api/lib/milos_training/identity/user.ex`**  
  Add field: `avatar_url :string`  
  Add changeset: `profile_changeset/2` — casts `[:nickname, :password, :avatar_url]`, applies normalize_nickname, validates nickname (3–30, format `/^[a-zA-Z0-9_]+$/`, unique), validates password (min 8), all conditionally if field present  
  Add changeset: `avatar_changeset/2` — casts `[:avatar_url]`

- [ ] **`apps/api/lib/milos_training/identity/account.ex`**  
  Add `avatar_url` to `@enforce_keys` (NO — keep it optional) and `defstruct`

- [ ] **`apps/api/lib/milos_training/infrastructure/identity/ecto_user_store.ex`**  
  Update `to_account/1`: add `avatar_url: user.avatar_url`  
  Add `update_profile/2`: fetch User, apply `profile_changeset`, call `maybe_put_password_hash`, `Repo.update`, return `{:ok, account}`  
  Add `update_avatar/2`: fetch User, apply `avatar_changeset`, `Repo.update`, return `{:ok, account}`  
  Add `search_users/1`: ILIKE on nickname, all roles, order by nickname, limit 20

- [ ] **`apps/api/lib/milos_training/identity/ports/user_store.ex`**  
  Add callbacks: `update_profile/2`, `update_avatar/2`, `search_users/1`

- [ ] **`apps/api/lib/milos_training/identity/user_store.ex`**  
  Add `@impl true` delegations for `update_profile/2`, `update_avatar/2`, `search_users/1`

- [ ] **`apps/api/lib/milos_training/identity.ex`**  
  Add: `defdelegate update_profile(user_id, params), to: UserStore`  
  Add: `defdelegate update_avatar(user_id, avatar_url), to: UserStore`  
  Add: `defdelegate search_users(query), to: FindUser, as: :search_all`  
  (Or keep `search_users` as a direct UserStore delegation if no FindUser query module needed)

- [ ] **`apps/api/lib/milos_training/infrastructure/storage/minio_storage.ex`**  
  Add `presigned_avatar_upload_url/1(user_id)`: generates PUT presigned URL + public URL  
  Add `avatar_ex_aws_config/0`: same as `ex_aws_config/0` but uses `minio_avatar_bucket`  
  Add `avatar_public_url/1(key)`: `#{minio_public_endpoint || minio_endpoint}/#{avatar_bucket}/#{key}`

- [ ] **`apps/api/lib/milos_training/notifications/domain/push_message_builder.ex`**  
  Add explicit clause BEFORE catch-all:
  ```elixir
  def build("chat_message", payload) do
    context = if payload["context_type"] in ["assignment", "class_slot"], do: " in your workout thread", else: ""
    %{
      title: "New message#{context}",
      body: payload["body"] || "You received a new message.",
      url: payload["url"] || "/"
    }
  end
  ```

- [ ] **`apps/api/lib/milos_training/notifications/ports/notification_store.ex`**  
  Add callback: `propagate_nickname_change(String.t(), String.t()) :: :ok`

- [ ] **`apps/api/lib/milos_training/notifications/notification_store.ex`**  
  Add `@impl true` delegation: `def propagate_nickname_change(old, new), do: adapter().propagate_nickname_change(old, new)`

- [ ] **`apps/api/lib/milos_training/notifications.ex`**  
  Add: `def propagate_nickname_change(old_nickname, new_nickname), do: NotificationStore.propagate_nickname_change(old_nickname, new_nickname)`

- [ ] **`apps/api/lib/milos_training/infrastructure/notifications/ecto_notification_store.ex`**  
  Implement `propagate_nickname_change/2` with two `Repo.query!` calls using `jsonb_set` + `to_jsonb($1::text)`

- [ ] **`apps/api/lib/milos_training_web/controllers/messaging_controller.ex`**  
  In the thread list action: collect all participant `user_id`s → call `Identity.list_by_ids/1` → build `%{user_id => account}` lookup map  
  Update `serialize_participant/1` to `serialize_participant/2` with the lookup map, adding `nickname` field  
  Update OpenAPI schema: add `nickname: %Schema{type: :string, nullable: true}` to participant schema

- [ ] **`apps/api/lib/milos_training_web/controllers/fallback_controller.ex`**  
  Add before the catch-all:
  ```elixir
  def call(conn, {:error, :invalid_current_password}) do
    conn |> put_status(:unprocessable_entity) |> json(%{error: "Current password is incorrect"})
  end
  ```

- [ ] **`apps/api/lib/milos_training_web/controllers/auth_controller.ex`**  
  Add `avatar_url: user.avatar_url` to `me` action response  
  Update `operation(:me)` OpenAPI schema: add `avatar_url` property (type string, nullable true)

- [ ] **`apps/api/lib/milos_training_web/router.ex`**  
  In the `/api/me` scope (authenticated), add:
  ```elixir
  patch("/profile", MeController, :update_profile)
  post("/avatar/upload-url", MeController, :avatar_upload_url)
  get("/search/users", MeController, :search_users)
  ```

### Infrastructure

- [ ] **`docker-compose.override.yml`**  
  Add to `api` service environment: `MINIO_AVATAR_BUCKET: ${MINIO_AVATAR_BUCKET:-milos-avatars}`

- [ ] **`.env.example`**  
  Add: `MINIO_AVATAR_BUCKET=milos-avatars`

### After backend changes

- [ ] **Run `cd apps/api && mix ecto.migrate`** to apply the new migration
- [ ] **Run `cd apps/api && mix format && mix credo --strict`** to validate
- [ ] **Run `cd apps/web && npm run generate:api`** to regenerate `schema.ts` and `openapi.json` from Elixir OpenAPI specs

### Frontend — New Files

- [ ] **`apps/web/src/api/profile.ts`**  
  ```typescript
  export type ProfileUpdate = { nickname?: string; current_password?: string; password?: string; avatar_url?: string; }
  export async function updateProfile(token, payload): Promise<{user: {id, nickname, role, avatar_url?}}>
  export async function getAvatarUploadUrl(token): Promise<{upload_url, public_url, key}>
  export async function searchAllUsers(token, query): Promise<Array<{id, nickname, role}>>
  ```

- [ ] **`apps/web/src/components/panels/WellbeingFormPanel.tsx`**  
  Dark-theme side panel with ONLY the form from `my-wellbeing.tsx` (no injury list)  
  Title: "Training Readiness" (not "Wellbeing")  
  Uses CSS vars: `--panel-muted`, `--border`, `--text`, `--muted`, etc.

- [ ] **`apps/web/src/components/panels/ReviewFormPanel.tsx`**  
  Dark-theme side panel with ONLY the review form (extracted from `my-reviews.tsx`)  
  No reviews list shown

- [ ] **`apps/web/src/app/profile/page.tsx`**  
  Route wrapper: `<AuthGuard><ProfilePage /></AuthGuard>`, `export const dynamic = "force-dynamic"`

- [ ] **`apps/web/src/components/ProfilePage.tsx`**  
  3 collapsible sections (same pattern as `admin-settings.tsx`):  
  - **Personal Info**: nickname change + password change (current password required)  
  - **Avatar**: presigned MinIO upload → PUT to upload_url → PATCH /api/me/profile with avatar_url  
  - **Account Activity** → subsection **My Reviews History**: read-only `<ReviewList />`  
  Uses `useSession()` for current user, refreshes after nickname change by calling session update

### Frontend — Modified Files

- [ ] **`apps/web/src/api/messaging.ts`**  
  Add `nickname?: string | null` to `ChatParticipant` interface  
  Change `searchUsers` function from calling `/admin/search?q=...` to calling `/me/search/users?q=...`  
  Return type now `Array<{id: string; nickname: string; role: string}>` (simpler, no pagination)

- [ ] **`apps/web/src/components/chat/DirectMessagesPanel.tsx`**  
  Thread list: `other?.nickname ?? "Direct message"` (was `other?.user_id`)  
  Avatar initials: `other?.nickname?.[0]?.toUpperCase()` (was `other?.user_id?.[0]`)  
  Search bar: uses updated `searchUsers` (now calls `/me/search/users`)  
  Sort search results: existing threads first (by recency), then alphabetically  

- [ ] **`apps/web/src/components/notifications/NotificationBell.tsx`**  
  Improve `chat_message` notification display:  
  When `notification.context_type === "assignment"`: show "New message in your workout thread"  
  Otherwise: show `notification.payload.body || "You received a new message"`

- [ ] **`apps/web/src/components/TopNav.tsx`**  
  Remove from `NAV_LINKS`: `{ href: "/reviews", ... }` and `{ href: "/wellbeing", ... }`  
  Add "Profile" link in user dropdown menu (before "Billing"): `<Link href="/profile">Profile</Link>`

- [ ] **`apps/web/src/components/my-reviews.tsx`**  
  Extract `ReviewForm` component (the form only, currently embedded)  
  Extract `ReviewList` component (the list only)  
  Keep `MyReviews` default export combining both (backward compatible for `/reviews` page if it exists)  
  Export `ReviewForm` and `ReviewList` as named exports

- [ ] **`apps/web/src/components/landing-page.tsx`**  
  Add 2 new state vars: `trainingReadinessOpen`, `reviewPanelOpen`  
  Add 2 buttons (non-admin only — check `currentUser.role !== "admin"`):  
    - "Training Readiness" → sets `trainingReadinessOpen(true)` → renders `<WellbeingFormPanel />`  
    - "Leave a Review" → sets `reviewPanelOpen(true)` → renders `<ReviewFormPanel />`  
  Import `WellbeingFormPanel`, `ReviewFormPanel`

- [ ] **`apps/web/src/components/admin-settings.tsx`**  
  Fix 3 ESLint `react-hooks/set-state-in-effect` errors:  
  Wrap setState calls inside useEffect in `queueMicrotask(() => { setState(...); setInitialized(true); })`  
  Affected locations: ~line 270 (`setForm` + `setInitialized`), ~line 405 (`setLevels` + `setInitialized`)

---

## 6. Validation Checklist (after implementation)

- [ ] `cd apps/api && mix format`
- [ ] `cd apps/api && mix credo --strict`
- [ ] `cd apps/api && mix test`
- [ ] `cd apps/web && npm run generate:api` (regenerate schema.ts from updated Elixir specs)
- [ ] `cd apps/web && npx tsc --noEmit` (TypeScript typecheck)
- [ ] `cd apps/web && npx next lint` (ESLint — expect 0 errors including admin-settings.tsx)
- [ ] Manual test: create MinIO bucket `milos-avatars` as public-read before testing avatar upload

---

## 7. Files NOT Changed

- `apps/web/src/api/generated/schema.ts` — generated, do not hand-edit
- `apps/web/src/api/generated/openapi.json` — generated, do not hand-edit
- `apps/api/lib/milos_training/messaging/participant.ex` — no schema change, nickname loaded at controller layer
- `apps/api/lib/milos_training/infrastructure/messaging/ecto_thread_store.ex` — no change, nickname batch-loaded in controller
- `apps/api/lib/milos_training/gamification/commands/refresh_leaderboard.ex` — existing, reused unchanged
