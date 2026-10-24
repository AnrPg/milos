defmodule Palee.Application.ListProfilePRs do
  @moduledoc """
  `GET /api/prs/profile/:user_id` (ADR-196): the PRs a person shows on their
  profile, as their followers see them. The read runs in the reader's own
  scope, so `user_pr_records_follower_read_policy` decides: the owner and
  their active followers get the PRs set to `followers`, anyone else none.
  """

  alias Palee.Pantheon

  def call(%{user_id: _reader_id} = context, owner_user_id) do
    case Ecto.UUID.cast(owner_user_id) do
      {:ok, owner_id} ->
        {:ok,
         Pantheon.with_user_context(context, fn ->
           owner_id
           |> Pantheon.list_profile_records()
           |> Enum.map(&Pantheon.read_only_view(&1, []))
         end)}

      :error ->
        {:error, :not_found}
    end
  end
end
