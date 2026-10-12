defmodule MilosTraining.Messaging.Domain.TenantDataPolicy do
  @moduledoc """
  Messaging tenant data retention and purge policy (ADR-099).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias MilosTraining.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "messaging",
            purge_order: 70,
            disposition: :purge,
            basis: "Direct messages are private communication with no retention obligation.",
            tables: [
              %{table: "messaging_participants"},
              %{table: "messaging_messages"},
              %{table: "messaging_threads"}
            ]
          })

  def policy, do: @policy
end
