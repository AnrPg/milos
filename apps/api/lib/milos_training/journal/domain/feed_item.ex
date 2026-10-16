defmodule MilosTraining.Journal.Domain.FeedItem do
  @moduledoc """
  One entry of the journal feed (ADR-139 §9), whatever its kind: when it
  happened, the gym it was recorded in, its rung and the rungs the member may
  move it to, and the entry itself as its own context reads it. The rungs a
  member may choose depend on the gym: a personal entry has no coach, so it
  can only be private.
  """

  alias MilosTraining.Journal.Domain.Visibility

  @type t :: %{
          kind: String.t(),
          id: Ecto.UUID.t(),
          occurred_at: DateTime.t(),
          occurred_tz: String.t() | nil,
          occurred_on: Date.t() | nil,
          organization_id: Ecto.UUID.t() | nil,
          journal_visibility: String.t(),
          choosable_visibilities: [String.t()],
          entry: map()
        }

  def build(kind, entry, %DateTime{} = occurred_at, opts \\ []) do
    organization_id = Map.get(entry, :organization_id)
    rung = if kind == "review", do: "rated", else: entry.journal_visibility

    %{
      kind: kind,
      id: entry.id,
      occurred_at: occurred_at,
      occurred_tz: Keyword.get(opts, :tz),
      occurred_on: Keyword.get(opts, :on),
      organization_id: organization_id,
      journal_visibility: rung,
      choosable_visibilities: choosable(kind, organization_id),
      entry: entry
    }
  end

  @doc "Rungs a member may move an entry of `kind` to, given its gym."
  def choosable(kind, organization_id) do
    kind
    |> Visibility.choosable()
    |> Enum.filter(&(is_binary(organization_id) or &1 == "private"))
  end
end
