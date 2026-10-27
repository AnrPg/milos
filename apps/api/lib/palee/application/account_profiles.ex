defmodule Palee.Application.AccountProfiles do
  @moduledoc """
  ADR-187: the profiles of the signed-in person's login. Listing them needs
  a session of one of them, which is the proof of owning the email; adding
  one or switching to one stays inside that login.
  """
  alias Palee.Application.{AccountDeletion, TokenIssuer}
  alias Palee.Identity

  # ADR-211: a profile scheduled for deletion is out of the list until undone.
  def list(%{login_id: login_id}),
    do:
      {:ok,
       Enum.filter(Identity.list_profiles(login_id), &(AccountDeletion.ensure_open(&1) == :ok))}

  def add(%{login_id: login_id}, params) do
    case Identity.add_profile(login_id, params) do
      {:error, :profile_limit} ->
        {:error, {:profile_limit, %{profile_limit: Identity.max_profiles()}}}

      result ->
        result
    end
  end

  @doc "A new session for another profile of the same login."
  def switch(%{login_id: login_id, id: current_id}, target_id) when is_binary(target_id) do
    with %{} = target <- Enum.find(Identity.list_profiles(login_id), &(&1.id == target_id)),
         :ok <- AccountDeletion.ensure_open(target),
         {:ok, tokens} <- TokenIssuer.issue_pair(target) do
      if target.id != current_id, do: Identity.touch_last_used(login_id, target.id)
      {:ok, Map.put(tokens, :user, target)}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def switch(_account, _target_id), do: {:error, :not_found}

  def handle_availability(handle, current_user_id \\ nil) when is_binary(handle) do
    alias Palee.Identity.Domain.Handle

    if Handle.valid?(handle) do
      normalized = Handle.normalize(handle)
      available = Identity.handle_available?(normalized, current_user_id)

      {:ok,
       %{
         available: available,
         handle: normalized,
         suggestions:
           if(available,
             do: [],
             else:
               normalized
               |> Handle.alternatives(6)
               |> Enum.filter(&Identity.handle_available?/1)
               |> Enum.take(3)
           )
       }}
    else
      {:error, :bad_request}
    end
  end

  def suggest_handle(display_name) when is_binary(display_name) do
    alias Palee.Identity.Domain.Handle

    case Handle.suggest(display_name) do
      nil ->
        nil

      candidate ->
        if Identity.handle_available?(candidate),
          do: candidate,
          else: candidate |> Handle.alternatives(6) |> Enum.find(&Identity.handle_available?/1)
    end
  end
end
