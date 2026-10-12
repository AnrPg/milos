defmodule MilosTraining.Application.GrantPRAccess do
  @moduledoc """
  Shares the owner's whole PR table, read-only, with another account
  (ADR-119). Any existing account may be picked; grants are global and not
  tied to a gym.
  """

  alias MilosTraining.Application.PRSharingProfiles
  alias MilosTraining.Pantheon

  def call(%{user_id: user_id} = context, params) when is_map(params) do
    with {:ok, grantee_user_id} <- grantee_id(params),
         {:ok, grantee} <- grantee_profile(grantee_user_id),
         {:ok, grant} <-
           Pantheon.with_user_context(context, fn ->
             Pantheon.grant_pr_access(user_id, grantee_user_id)
           end) do
      {:ok, %{id: grant.id, created_at: grant.created_at, grantee: grantee}}
    end
  end

  defp grantee_id(params) do
    case Ecto.UUID.cast(params["grantee_user_id"] || params[:grantee_user_id]) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :bad_request}
    end
  end

  defp grantee_profile(grantee_user_id) do
    case PRSharingProfiles.call([grantee_user_id]) do
      %{^grantee_user_id => profile} -> {:ok, profile}
      _missing -> {:error, :not_found}
    end
  end
end
