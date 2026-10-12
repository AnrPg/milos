defmodule MilosTraining.Application.RevokePRAccess do
  @moduledoc "Revokes one of the owner's PR sharing grants (ADR-119)."

  alias MilosTraining.Pantheon

  def call(%{user_id: user_id} = context, grant_id) do
    with {:ok, grant_id} <- cast_id(grant_id),
         {:ok, _grant} <-
           Pantheon.with_user_context(context, fn ->
             Pantheon.revoke_pr_access(user_id, grant_id)
           end) do
      :ok
    end
  end

  defp cast_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end
end
