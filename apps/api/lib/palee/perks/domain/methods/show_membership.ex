defmodule Palee.Perks.Domain.Methods.ShowMembership do
  @moduledoc """
  No code (ADR-191 §2): the member shows their membership card at the
  partner. A claim still records the use of the perk and carries a short
  reference for the business's export.
  """
  @behaviour Palee.Perks.Domain.RedemptionMethod

  @impl true
  def key, do: "show_membership"
  @impl true
  def validate(_settings), do: []
  @impl true
  def issue, do: :reference
  @impl true
  def verifiable?, do: false
  @impl true
  def ready(_facts), do: :ok
  @impl true
  def reveal(_settings, _code), do: %{code: nil, url: nil, show_membership: true}
end
