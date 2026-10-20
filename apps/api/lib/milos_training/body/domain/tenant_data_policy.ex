defmodule MilosTraining.Body.Domain.TenantDataPolicy do
  @moduledoc """
  Body tenant data retention and purge policy (ADR-117, ADR-158).

  Body snapshots, photos, consents and settings are the person's own
  (account-scoped) and never part of a gym's data. The only gym-scoped rows
  are the audit of that gym's coaches reading shared snapshots.
  """

  alias MilosTraining.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "body",
            purge_order: 46,
            disposition: :purge,
            basis:
              "Coach-read audit rows of members' body snapshots only matter while the gym exists; the snapshots stay with the member.",
            tables: [%{table: "body_access_log"}]
          })

  def policy, do: @policy
end
