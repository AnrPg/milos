defmodule Palee.Messaging.Domain.TenantDataPolicy do
  @moduledoc """
  Messaging tenant data retention and purge policy (ADR-117).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "messaging",
            purge_order: 70,
            disposition: :purge,
            basis: "Direct messages are private communication with no retention obligation.",
            tables: [
              %{table: "messaging_box_blocks"},
              %{table: "messaging_participants"},
              %{table: "messaging_messages"},
              %{table: "messaging_threads"}
            ]
          })

  def policy, do: @policy
end
