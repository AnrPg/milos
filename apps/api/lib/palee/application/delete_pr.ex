defmodule Palee.Application.DeletePR do
  alias Palee.Application.{InvalidateLandingPages, PRSearchIndex}
  alias Palee.Pantheon

  # Owner-only under RLS: runs in the acting user's scope (ADR-129).
  def call(%{user_id: user_id} = context, id),
    do: Pantheon.with_user_context(context, fn -> call(id, user_id) end)

  def call(id, user_id) do
    case Pantheon.delete_record(id, user_id) do
      :ok ->
        :ok = PRSearchIndex.enqueue_delete(id, user_id)
        InvalidateLandingPages.for_users([user_id])
        :ok

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end
end
