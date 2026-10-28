defmodule Palee.Repo.Migrations.MemberRenewalChoiceAndLeaving do
  @moduledoc """
  ADR-220: the member chooses whether a subscription renews, and a member
  can leave the box (or staff mark them as left).

  - `membership_package_subscriptions.auto_renew`: the member's choice. A
    package's `terms.auto_renew` now only says whether its subscriptions may
    renew; existing subscriptions keep renewing (`true`).
  - `renewal_changed_at` / `renewal_changed_by` (`member` | `staff`): who
    turned it off or on last, shown to staff.
  - `ends_on_from_renewal_stop`: turning renewal off gave an open-ended
    subscription its last day in `ends_on`; turning it back on clears it.
  - `memberships.leaving_on` (last day of access), `left_at`, `left_by`
    (`member` | `staff`) and `leave_reason`.
  - Notification type `member_leaving` (staff hear that a member is leaving).
  """

  use Ecto.Migration

  @notification_types ~w(member_leaving)

  def up do
    alter table(:membership_package_subscriptions) do
      add :auto_renew, :boolean, null: false, default: true
      add :renewal_changed_at, :utc_datetime_usec
      add :renewal_changed_by, :string
      add :ends_on_from_renewal_stop, :boolean, null: false, default: false
    end

    create constraint(:membership_package_subscriptions, :renewal_changed_by_check,
             check: "renewal_changed_by IS NULL OR renewal_changed_by IN ('member', 'staff')"
           )

    alter table(:memberships) do
      add :leaving_on, :date
      add :left_at, :utc_datetime_usec
      add :left_by, :string
      add :leave_reason, :text
    end

    create constraint(:memberships, :left_by_check,
             check: "left_by IS NULL OR left_by IN ('member', 'staff')"
           )

    create constraint(:memberships, :leaving_consistency_check,
             check: "(left_at IS NULL) = (leaving_on IS NULL) AND (left_at IS NULL) = (left_by IS NULL)"
           )

    add_notification_types(@notification_types)
  end

  def down do
    execute("DELETE FROM notifications WHERE type IN (#{in_list(@notification_types)})")
    remove_notification_types(@notification_types)

    drop constraint(:memberships, :leaving_consistency_check)
    drop constraint(:memberships, :left_by_check)

    alter table(:memberships) do
      remove :leave_reason
      remove :left_by
      remove :left_at
      remove :leaving_on
    end

    drop constraint(:membership_package_subscriptions, :renewal_changed_by_check)

    alter table(:membership_package_subscriptions) do
      remove :ends_on_from_renewal_stop
      remove :renewal_changed_by
      remove :renewal_changed_at
      remove :auto_renew
    end
  end

  defp add_notification_types(types), do: rewrite_notification_types(&Enum.uniq(&1 ++ types))
  defp remove_notification_types(types), do: rewrite_notification_types(&(&1 -- types))

  # The same read-modify-write of notifications_type_check as earlier
  # migrations, so types other migrations added stay.
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

  defp in_list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
