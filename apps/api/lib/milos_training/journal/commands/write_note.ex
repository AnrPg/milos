defmodule MilosTraining.Journal.Commands.WriteNote do
  @moduledoc """
  Writes a Σημείωση. It starts on the member's `note` default rung when
  written in a gym, and is private when written personally (ADR-139).
  """

  alias MilosTraining.Journal.Domain.Visibility
  alias MilosTraining.Journal.JournalStore

  @fields ~w(topic body linked_kind linked_id written_at written_tz)a

  def call(user_id, organization_id, params, %DateTime{} = now) do
    defaults = JournalStore.list_defaults(user_id)

    params
    |> attrs()
    |> Map.put_new(:written_at, now)
    |> Map.merge(%{
      user_id: user_id,
      organization_id: organization_id,
      journal_visibility: Visibility.initial("note", defaults, is_binary(organization_id))
    })
    |> JournalStore.create_note()
  end

  @doc false
  def attrs(params) do
    for field <- @fields,
        key = Atom.to_string(field),
        Map.has_key?(params, key) or Map.has_key?(params, field),
        into: %{} do
      {field, Map.get(params, key, Map.get(params, field))}
    end
    |> Map.reject(fn {key, value} -> key == :written_at and is_nil(value) end)
  end
end
