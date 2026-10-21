defmodule MilosTraining.Buddies.Domain.TenantDataPolicy do
  @moduledoc """
  Buddies tenant data retention and purge policy (ADR-117, ADR-160).

  Buddy links, support requests, the buddy conversation and the summary
  toggles are the person's own (account-scoped) and never part of a gym's
  data. The only gym-scoped rows are the audit of that gym's coaches
  reading members' weekly wellness summaries.
  """

  alias MilosTraining.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "buddies",
            purge_order: 47,
            disposition: :purge,
            basis:
              "Coach-read audit rows of members' weekly wellness summaries only matter while the gym exists; the wellness data stays with the member.",
            tables: [%{table: "wellness_access_log"}]
          })

  def policy, do: @policy
end
