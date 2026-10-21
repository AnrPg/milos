defmodule Palee.Application.CommunityPeople do
  @moduledoc "People as the community screens show them (ADR-143): id, nickname, avatar."

  alias Palee.Identity

  def by_ids(ids) do
    ids
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] -> %{}
      ids -> ids |> Identity.list_by_ids() |> Map.new(&{&1.id, person(&1)})
    end
  end

  def person(people, id), do: Map.get(people, id) || %{id: id, nickname: nil, avatar_url: nil}

  defp person(user),
    do: %{id: user.id, nickname: user.nickname, avatar_url: Map.get(user, :avatar_url)}
end
