defmodule Palee.Community.Commands.SetNotifyLevel do
  @moduledoc "How much a member hears from a club: all, announcements only, or nothing (ADR-138)."

  alias Palee.Community.{ClubMembership, CommunityStore}

  def call(%{organization_id: organization_id, user_id: user_id} = context, club_id, level) do
    with :ok <- validate(level),
         %{organization_id: ^organization_id} = club <- CommunityStore.get_club(context, club_id),
         :ok <- member_of(context, club, user_id) do
      CommunityStore.put_notify_level(context, club, user_id, level)
    else
      {:error, _reason} = error -> error
      _missing -> {:error, :not_found}
    end
  end

  # An open club's membership is its row (ADR-143): a level never creates one.
  defp member_of(context, %{kind: "open"} = club, user_id) do
    case CommunityStore.get_club_membership(context, club.id, user_id) do
      %{status: "active"} -> :ok
      _none -> {:error, :not_found}
    end
  end

  defp member_of(_context, _club, _user_id), do: :ok

  defp validate(level),
    do:
      if(level in ClubMembership.notify_levels(),
        do: :ok,
        else: {:error, :invalid_notify_level}
      )
end
