defmodule Palee.Repo.Migrations.V31SoldOnline do
  @moduledoc """
  ADR-271: «Πωλείται online» opens by itself when the box connects online
  payments. A package remembers when its owner chose (`sold_online_chosen_at`)
  so Palee never switches it back on; the payment account remembers the one
  time it opened the paid packages and whether the owner has seen the notice.
  """
  use Ecto.Migration

  def change do
    alter table(:membership_packages) do
      add :sold_online_chosen_at, :utc_datetime_usec
    end

    alter table(:payment_accounts) do
      add :packages_opened_at, :utc_datetime_usec
      add :packages_opened_count, :integer
      add :packages_notice_dismissed_at, :utc_datetime_usec
    end
  end
end
