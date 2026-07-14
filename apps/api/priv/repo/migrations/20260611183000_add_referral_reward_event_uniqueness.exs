defmodule MilosTraining.Repo.Migrations.AddReferralRewardEventUniqueness do
  use Ecto.Migration

  def up do
    drop_if_exists index(:referral_rewards, [:referral_event_id])
    create unique_index(:referral_rewards, [:referral_event_id])
  end

  def down do
    drop_if_exists unique_index(:referral_rewards, [:referral_event_id])
    create index(:referral_rewards, [:referral_event_id])
  end
end
