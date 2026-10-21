defmodule MilosTraining.Community.Commands.Blocks do
  @moduledoc """
  Blocking a person (ADR-169 §5). One row per person blocked; blocking
  twice is a no-op, nobody blocks themselves. Whom one blocked or was
  blocked by is answered for the session user only.
  """

  alias MilosTraining.Community.SocialStore

  def block(%{user_id: user_id}, user_id), do: {:error, :cannot_block_self}

  def block(%{user_id: user_id} = context, blocked_id) when is_binary(blocked_id),
    do: SocialStore.insert_block(context, %{user_id: user_id, blocked_user_id: blocked_id})

  def block(_context, _blocked_id), do: {:error, :invalid_user}

  def unblock(%{user_id: user_id} = context, blocked_id),
    do: SocialStore.delete_block(context, user_id, blocked_id)

  def list(%{user_id: user_id} = context), do: SocialStore.list_blocks(context, user_id)

  @doc "Everyone the session user blocked or was blocked by."
  def blocked_ids(context), do: SocialStore.blocked_user_ids(context)
end
