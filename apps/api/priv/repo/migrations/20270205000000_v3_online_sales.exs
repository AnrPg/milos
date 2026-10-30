defmodule Palee.Repo.Migrations.V3OnlineSales do
  @moduledoc """
  ADR-248: packages a box sells online, and what an online payment is for
  beyond its purpose row (the class to book after a package purchase, the
  payer's request to start before the 14-day withdrawal period ends).
  """
  use Ecto.Migration

  def change do
    alter table(:membership_packages) do
      add :sold_online, :boolean, null: false, default: false
    end

    alter table(:payment_intents) do
      add :metadata, :map, null: false, default: %{}
    end
  end
end
