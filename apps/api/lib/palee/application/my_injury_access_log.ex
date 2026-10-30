defmodule Palee.Application.MyInjuryAccessLog do
  @moduledoc "Who of your boxes' staff read your injuries, newest first (ADR-286)."

  alias Palee.{Identity, Organizations, Wellbeing}

  @limit 200

  def call(%{user_id: user_id} = context) do
    entries =
      Wellbeing.with_tenant_context(context, fn ->
        Wellbeing.list_injury_access_log(user_id, @limit)
      end)

    readers =
      entries
      |> Enum.map(& &1.reader_user_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Identity.list_by_ids()
      |> Map.new(&{&1.id, &1.nickname})

    gyms =
      entries
      |> Enum.map(& &1.organization_id)
      |> Enum.uniq()
      |> Map.new(fn id ->
        {id,
         case Organizations.get_by_id(id) do
           %{name: name} -> name
           _missing -> nil
         end}
      end)

    {:ok,
     Enum.map(entries, fn entry ->
       %{
         id: entry.id,
         read_at: entry.read_at,
         surface: entry.surface,
         injury_ids: entry.injury_ids,
         reader: %{id: entry.reader_user_id, nickname: Map.get(readers, entry.reader_user_id)},
         organization: %{id: entry.organization_id, name: Map.get(gyms, entry.organization_id)}
       }
     end)}
  end
end
