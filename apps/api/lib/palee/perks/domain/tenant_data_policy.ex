defmodule Palee.Perks.Domain.TenantDataPolicy do
  @moduledoc """
  Perks tenant data retention and purge policy (ADR-117, ADR-191).

  Partner perks, their code pools and the members' claims are operational
  data with no retention obligation of their own (no money moves through
  Palee). They reference packages and branches only by plain ids, so they
  are purged early, before Finance and Facility.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "perks",
            purge_order: 84,
            disposition: :purge,
            basis:
              "Partner perks, their code pools and claims are operational data; no payment moves through Palee. They name packages and branches by plain ids, so they purge before Finance and Facility.",
            tables: [
              %{table: "perk_claims"},
              %{table: "perk_codes"},
              %{table: "perks"}
            ],
            # The hash behind a verification link is a credential, never exported.
            excluded_columns: ["token_hash"]
          })

  def policy, do: @policy
end
