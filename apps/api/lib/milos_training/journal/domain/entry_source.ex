defmodule MilosTraining.Journal.Domain.EntrySource do
  @moduledoc """
  Where a journal entry came from (ADR-162), as every cross-provider view
  labels it: `organization` (recorded at a provider, a gym or an independent
  coach), `device` (Garmin and later Apple Health / Health Connect, ADR-149)
  or `freeform` (recorded on the member's own, without a provider).

  The label carries the provider's name and `former: true` once the member's
  membership there ended (board 17, Q6: the history stays theirs, labelled
  «πρώην»). Filters name sources by token: a provider id, `freeform` or
  `device`.
  """

  @device_sources ~w(garmin apple_health health_connect)
  @device_names %{
    "garmin" => "Garmin",
    "apple_health" => "Apple Health",
    "health_connect" => "Health Connect"
  }

  @type t :: %{
          kind: String.t(),
          organization_id: String.t() | nil,
          name: String.t() | nil,
          former: boolean()
        }

  def device_sources, do: @device_sources
  def device_source?(source), do: to_string(source) in @device_sources

  @doc """
  The label of an entry. `directory` maps organization ids to
  `%{name: name, former: boolean}`; a provider missing from it (an
  organization the member never belonged to, or one that was deleted) is
  labelled without a name and as former.
  """
  def label(organization_id, device_source, directory) do
    cond do
      is_binary(device_source) and device_source in @device_sources ->
        %{
          kind: "device",
          organization_id: nil,
          name: Map.fetch!(@device_names, device_source),
          former: false
        }

      is_binary(organization_id) ->
        provider = Map.get(directory, organization_id, %{name: nil, former: true})

        %{
          kind: "organization",
          organization_id: organization_id,
          name: provider.name,
          former: provider.former
        }

      true ->
        %{kind: "freeform", organization_id: nil, name: nil, former: false}
    end
  end

  @doc "The filter token of a label."
  def token(%{kind: "organization", organization_id: id}), do: id
  def token(%{kind: kind}), do: kind

  @doc "Does a label match any of `tokens` (an empty list matches everything)?"
  def matches?(_label, []), do: true
  def matches?(label, tokens), do: token(label) in tokens
end
