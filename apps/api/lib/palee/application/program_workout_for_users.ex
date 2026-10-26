defmodule Palee.Application.ProgramWorkoutForUsers do
  @moduledoc """
  Programs one workout for several people at once (ADR-201).

  Every person in the list is treated as if they were the only one:
  `ProgramUserWorkout.call/4` runs once per person with the same params, after
  the same client-access check the one-person endpoint makes. Each person gets
  their own copy, filed in their own folder, and the result lists the outcome
  per person. One person failing never undoes the others.

  Ids are deduplicated (first occurrence keeps its place) and the list is
  capped at 50 people.
  """

  alias Palee.Application.{AuthorizeClientAccess, ProgramUserWorkout}

  @max_users 50

  @doc "The most people one request may program."
  def max_users, do: @max_users

  def call(context, admin, user_ids, params) when is_list(user_ids) do
    case normalize_ids(user_ids) do
      [] ->
        {:error, :invalid_user_ids}

      ids when length(ids) > @max_users ->
        {:error, :too_many_users}

      ids ->
        params = Map.drop(params, [:user_ids, "user_ids"])
        {:ok, %{results: Enum.map(ids, &program_one(context, admin, &1, params))}}
    end
  end

  def call(_context, _admin, _user_ids, _params), do: {:error, :invalid_user_ids}

  defp program_one(context, admin, user_id, params) do
    with :ok <- authorize(context, user_id),
         {:ok, payload} <- ProgramUserWorkout.call(context, admin, user_id, params) do
      payload |> Map.put(:user_id, user_id) |> Map.put(:status, "ok")
    else
      error -> error_result(user_id, error)
    end
  end

  # The one-person endpoint refuses a coach with scope `:own` for anyone who is
  # not their client (ADR-100); the same check runs here for each person.
  defp authorize(context, user_id) do
    case AuthorizeClientAccess.call(context, :manage_coaching, user_id) do
      :ok -> :ok
      _denied -> {:error, :not_your_client}
    end
  end

  defp error_result(user_id, {:error, reason, details}) when is_atom(reason) and is_map(details),
    do: %{user_id: user_id, status: "error", code: to_string(reason), params: details}

  defp error_result(user_id, {:error, %Ecto.Changeset{}}),
    do: %{user_id: user_id, status: "error", code: "validation_failed"}

  defp error_result(user_id, {:error, {reason, details}})
       when is_atom(reason) and is_map(details),
       do: %{user_id: user_id, status: "error", code: to_string(reason), params: details}

  defp error_result(user_id, {:error, reason}) when is_atom(reason),
    do: %{user_id: user_id, status: "error", code: to_string(reason)}

  defp error_result(user_id, _other),
    do: %{user_id: user_id, status: "error", code: "unexpected_server_error"}

  defp normalize_ids(user_ids) do
    user_ids
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end
end
