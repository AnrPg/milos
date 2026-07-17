defmodule MilosTraining.Repo.Migrations.AddStructuredDetailsToPrResults do
  use Ecto.Migration

  def change do
    alter table(:user_pr_records) do
      add(:supporting_metrics, :map, null: false, default: %{})
      add(:notes, :text)
    end

    alter table(:user_pr_history) do
      add(:supporting_metrics, :map, null: false, default: %{})
      add(:notes, :text)
    end
  end
end
