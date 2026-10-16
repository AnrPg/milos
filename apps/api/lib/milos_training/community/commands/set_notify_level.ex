defmodule MilosTraining.Community.Commands.SetNotifyLevel do
  @moduledoc "How much a member hears from a club: all, announcements only, or nothing (ADR-138)."

  alias MilosTraining.Community.{ClubMembership, CommunityStore}

  def call(%{organization_id: organization_id, user_id: user_id} = context, club_id, level) do
    with :ok <- validate(level),
         %{organization_id: ^organization_id} = club <- CommunityStore.get_club(context, club_id) do
      CommunityStore.put_notify_level(context, club, user_id, level)
    else
      {:error, _reason} = error -> error
      _missing -> {:error, :not_found}
    end
  end

  defp validate(level),
    do:
      if(level in ClubMembership.notify_levels(),
        do: :ok,
        else: {:error, :invalid_notify_level}
      )
end
