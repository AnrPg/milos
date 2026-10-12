defmodule MilosTraining.Application.PRSharingProfiles do
  @moduledoc """
  Public account identity (ADR-111) for the people on either side of a PR
  sharing grant: just enough to recognise them, never contact details.
  """

  alias MilosTraining.Identity

  def call(user_ids) when is_list(user_ids) do
    user_ids
    |> Enum.uniq()
    |> Identity.list_by_ids()
    |> Map.new(fn user ->
      {user.id,
       %{
         id: user.id,
         nickname: user.nickname,
         display_nickname: Map.get(user, :display_nickname) || user.nickname,
         avatar_url: Map.get(user, :avatar_url)
       }}
    end)
  end
end
