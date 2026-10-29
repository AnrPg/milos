defmodule Palee.BoxScreens.Domain.TenantDataPolicy do
  @moduledoc """
  Box screen tenant data retention and purge policy (ADR-117, ADR-253).
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "box_screens",
            purge_order: 6,
            disposition: :purge,
            basis:
              "Box screens are device settings (name, branch, what they show) with no retention obligation; purged before Facility because a screen names a branch.",
            tables: [%{table: "box_screens"}],
            # ADR-253: the pending pairing code's hash is a credential.
            excluded_columns: ["pairing_code_hash"]
          })

  def policy, do: @policy
end
