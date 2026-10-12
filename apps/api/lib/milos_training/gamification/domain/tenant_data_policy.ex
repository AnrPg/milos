defmodule MilosTraining.Gamification.Domain.TenantDataPolicy do
  @moduledoc """
  Gamification tenant data retention and purge policy (ADR-107).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias MilosTraining.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "gamification",
            purge_order: 80,
            disposition: :purge,
            basis:
              "Challenges, opt-ins and achievements are engagement data with no retention obligation.",
            tables: [
              %{table: "user_challenge_progress"},
              %{table: "challenge_leaderboard_opt_ins"},
              %{table: "seasonal_challenges"},
              %{table: "leaderboard_opt_ins"},
              %{table: "user_achievements", rls: :user},
              %{table: "gamification_settings"}
            ]
          })

  def policy, do: @policy
end
