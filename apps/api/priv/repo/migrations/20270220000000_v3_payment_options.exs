defmodule Palee.Repo.Migrations.V3PaymentOptions do
  @moduledoc """
  ADR-260: what a business lets its members pay online and who hears about a
  failed charge (`payment_accounts.options`), staff closing a failed charge
  in the Ουρές queue (`payment_intents.attention_*`), and the two
  notifications of a declined saved-card charge.
  """
  use Ecto.Migration

  @types ~w(payment_failed payment_needs_attention)

  def up do
    alter table(:payment_accounts) do
      add :options, :map, null: false, default: %{}
    end

    alter table(:payment_intents) do
      add :attention_resolved_at, :utc_datetime_usec
      add :attention_resolved_by_id, :binary_id
      add :attention_resolution, :string
    end

    create constraint(:payment_intents, :payment_intents_attention_resolution_check,
             check: "attention_resolution IS NULL OR attention_resolution IN ('dismissed')"
           )

    rewrite_notification_types(&Enum.uniq(&1 ++ @types))
  end

  def down do
    execute(
      "DELETE FROM notifications WHERE type IN ('payment_failed', 'payment_needs_attention')"
    )

    rewrite_notification_types(&(&1 -- @types))

    drop constraint(:payment_intents, :payment_intents_attention_resolution_check)

    alter table(:payment_intents) do
      remove :attention_resolved_at
      remove :attention_resolved_by_id
      remove :attention_resolution
    end

    alter table(:payment_accounts) do
      remove :options
    end
  end

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
      "ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (#{Enum.map_join(change.(current), ", ", &"'#{&1}'")}))"
    )
  end
end
