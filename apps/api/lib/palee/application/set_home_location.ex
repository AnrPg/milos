defmodule Palee.Application.SetHomeLocation do
  @moduledoc """
  Sets the home location of a person in a gym (Phase 2): the location their
  schedule and Box open on. A person may set their own; staff who manage
  memberships may set anyone's. Only an active location of the gym qualifies;
  `nil` clears it.
  """

  alias Palee.{Facility, Organizations}

  def call(context, user_id, location_id) when is_binary(user_id) do
    with :ok <- authorize(context, user_id),
         :ok <- usable_location(context, location_id) do
      Organizations.put_home_location(context, user_id, location_id)
    end
  end

  def call(_context, _user_id, _location_id), do: {:error, :not_found}

  defp authorize(%{user_id: user_id}, user_id), do: :ok

  defp authorize(context, _user_id) do
    if Organizations.can?(context, :manage_memberships), do: :ok, else: {:error, :forbidden}
  end

  defp usable_location(_context, nil), do: :ok

  defp usable_location(context, location_id) when is_binary(location_id) do
    case Ecto.UUID.cast(location_id) do
      {:ok, id} ->
        case Facility.get_location(context, id) do
          %{archived_at: nil} -> :ok
          _missing_or_archived -> {:error, [location_id: "is not an active location of this gym"]}
        end

      :error ->
        {:error, [location_id: "is invalid"]}
    end
  end

  defp usable_location(_context, _location_id), do: {:error, [location_id: "is invalid"]}
end
