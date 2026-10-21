defmodule Palee.Application.PeopleBlocks do
  @moduledoc """
  Blocking a person (ADR-169 §5): the two never meet in Partners again,
  every active Partners match between them ends (`blocked`) and any buddy
  link between them ends at once (`Buddies.end_for_block`, ADR-160). The
  block is the person's own (account-scoped); the other person is not told.
  Unblocking lifts the block only: ended matches and links stay ended.
  """

  alias Palee.Application.{Buddies, CommunityPeople, PartnerMatches}
  alias Palee.Community

  @doc "Blocks `blocked_id`; `reason` is how Partners matches end (`blocked` or `reported`)."
  def block(context, blocked_id, reason \\ "blocked") do
    with {:ok, blocked_id} <- cast_id(blocked_id),
         {:ok, _block} <- Community.block_user(personal(context), blocked_id),
         :ok <- PartnerMatches.end_between(context, blocked_id, reason),
         :ok <- Buddies.end_for_block(personal(context), blocked_id) do
      {:ok, %{user_id: blocked_id, blocked: true}}
    end
  end

  def unblock(context, blocked_id) do
    with {:ok, blocked_id} <- cast_id(blocked_id),
         :ok <- Community.unblock_user(personal(context), blocked_id) do
      {:ok, %{user_id: blocked_id, blocked: false}}
    end
  end

  @doc "The people the viewer blocked, newest first."
  def list(context) do
    blocks = Community.list_blocks(personal(context))
    people = CommunityPeople.by_ids(Enum.map(blocks, & &1.blocked_user_id))

    {:ok,
     %{
       blocks:
         Enum.map(blocks, fn block ->
           %{
             person: CommunityPeople.person(people, block.blocked_user_id),
             blocked_at: block.inserted_at
           }
         end)
     }}
  end

  # Blocks are account-scoped: a personal session, whatever route asked.
  defp personal(%{user_id: user_id} = context),
    do: context |> Map.take([:account]) |> Map.put(:user_id, user_id)

  defp cast_id(id) do
    case Ecto.UUID.cast(id || "") do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end
end
