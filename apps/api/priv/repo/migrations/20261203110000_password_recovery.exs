defmodule Palee.Repo.Migrations.PasswordRecovery do
  @moduledoc """
  ADR-187: password recovery without a mail service.

  - `password_reset_requests`: at most one open request per login. A handler
    (vendor, the owner/admin/front desk of a box the person belongs to, or
    the person's coach) claims it, then issues a one-time reset link that
    they mail from their own mailbox. Only the link's hash is stored. A
    used, rejected or dismissed request is deleted; an issued link that
    expires keeps the row so lists can show it as expired.
  - `password_reset_request_hides`: a handler hiding a request from their
    own list, for good.
  - `password_reset_log`: the security log the vendor reads. Snapshots the
    names so it survives deleted profiles.
  - `login_recovery_codes`: optional one-time codes the person keeps
    offline (hashed).
  - `palee_password_reset_handlers(login)`: who may handle a login's
    request. A definer function because the box and coaching links live in
    tenant tables the unauthenticated request cannot read.
  """
  use Ecto.Migration

  @notification_types ~w(password_reset_requested password_reset_completed)

  def up do
    create table(:password_reset_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :login_id, references(:logins, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "open"
      add :claimed_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :claimed_at, :utc_datetime_usec
      add :link_token_hash, :binary
      add :link_expires_at, :utc_datetime_usec
      add :link_issued_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :link_issued_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:password_reset_requests, [:login_id])
    create unique_index(:password_reset_requests, [:link_token_hash])

    create constraint(:password_reset_requests, :password_reset_requests_status,
             check: "status IN ('open', 'link_issued')"
           )

    create table(:password_reset_request_hides, primary_key: false) do
      add :request_id,
          references(:password_reset_requests, type: :binary_id, on_delete: :delete_all),
          primary_key: true

      add :viewer_user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create table(:password_reset_log, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :login_id, references(:logins, type: :binary_id, on_delete: :nilify_all)
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :handle, :string
      add :handler_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :handler_handle, :string
      add :event, :string, null: false
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create index(:password_reset_log, ["inserted_at DESC"])

    create constraint(:password_reset_log, :password_reset_log_event,
             check:
               "event IN ('requested', 'claimed', 'released', 'link_issued', 'completed', " <>
                 "'rejected', 'dismissed', 'recovery_code_used')"
           )

    create table(:login_recovery_codes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :login_id, references(:logins, type: :binary_id, on_delete: :delete_all), null: false
      add :code_hash, :binary, null: false
      add :used_at, :utc_datetime_usec
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create index(:login_recovery_codes, [:login_id])

    execute("""
    CREATE FUNCTION palee_password_reset_handlers(p_login_id uuid)
    RETURNS TABLE (user_id uuid, source text, organization_id uuid, organization_name text)
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      WITH profiles AS (
        SELECT u.id FROM public.users u WHERE u.login_id = p_login_id
      ), handlers AS (
        SELECT v.user_id, 'vendor'::text AS source, NULL::uuid AS organization_id,
               NULL::text AS organization_name
        FROM public.vendors v
        WHERE v.status = 'active'
        UNION
        SELECT staff.user_id, 'box', o.id, o.name::text
        FROM public.organization_memberships person
        JOIN public.organization_memberships staff
          ON staff.organization_id = person.organization_id
         AND staff.status = 'active'
         AND staff.roles && ARRAY['owner', 'admin', 'front_desk']::varchar[]
        JOIN public.organizations o ON o.id = person.organization_id
        WHERE person.user_id IN (SELECT id FROM profiles)
          AND person.status = 'active'
        UNION
        SELECT c.coach_user_id, 'coach', o.id, o.name::text
        FROM public.coaching_relationships c
        JOIN public.organizations o ON o.id = c.organization_id
        WHERE c.client_user_id IN (SELECT id FROM profiles)
          AND c.ended_at IS NULL
      )
      SELECT h.user_id, h.source, h.organization_id, h.organization_name
      FROM handlers h
      WHERE h.user_id NOT IN (SELECT id FROM profiles)
    $$
    """)

    add_notification_types(@notification_types)
  end

  def down do
    execute("DELETE FROM notifications WHERE type IN (#{in_list(@notification_types)})")
    remove_notification_types(@notification_types)
    execute("DROP FUNCTION palee_password_reset_handlers(uuid)")
    drop table(:login_recovery_codes)
    drop table(:password_reset_log)
    drop table(:password_reset_request_hides)
    drop table(:password_reset_requests)
  end

  defp add_notification_types(types), do: rewrite_notification_types(&Enum.uniq(&1 ++ types))
  defp remove_notification_types(types), do: rewrite_notification_types(&(&1 -- types))

  defp rewrite_notification_types(change) do
    flush()

    %{rows: [[definition]]} =
      repo().query!("""
      SELECT pg_get_constraintdef(oid) FROM pg_constraint
      WHERE conname = 'notifications_type_check' AND conrelid = 'notifications'::regclass
      """)

    current = Regex.scan(~r/'([a-z0-9_]+)'/, definition) |> Enum.map(&List.last/1)

    execute("ALTER TABLE notifications DROP CONSTRAINT notifications_type_check")

    execute(
      "ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (#{in_list(change.(current))}))"
    )
  end

  defp in_list(types), do: Enum.map_join(types, ", ", &"'#{&1}'")
end
