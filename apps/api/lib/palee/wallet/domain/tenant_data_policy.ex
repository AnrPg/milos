defmodule Palee.Wallet.Domain.TenantDataPolicy do
  @moduledoc """
  Wallet tenant data retention and purge policy (ADR-117, ADR-155).

  Members' Wallet cards and the devices registered for their updates are
  operational data with no retention obligation. Device registrations are
  children of a pass. Pass and device secrets are never exported.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "wallet",
            purge_order: 87,
            disposition: :purge,
            basis:
              "Wallet cards and their device registrations are operational data with no retention obligation; nothing else references them.",
            tables: [
              %{table: "wallet_device_registrations", parent: {"wallet_passes", "pass_id"}},
              %{table: "wallet_passes"}
            ],
            excluded_columns: ["auth_token_hash", "push_token"]
          })

  def policy, do: @policy
end
