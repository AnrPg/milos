defmodule Palee.Community.Commands.Follows do
  @moduledoc """
  Following and the follow requests a person answers (ADR-142, D3). Runs in
  the acting member's personal session: the follower's own rows, or the
  rows that target them.
  """

  alias Palee.Community.Domain.FollowPolicy
  alias Palee.Community.SocialStore

  @doc """
  Follows `target` (what the caller found for `type`/`target_id`, or nil).
  Following again returns the existing row unchanged.
  """
  def follow(%{user_id: user_id} = context, type, target_id, target) do
    with :ok <- FollowPolicy.check(user_id, type, target) do
      case SocialStore.get_follow(context, user_id, type, target_id) do
        nil ->
          status = FollowPolicy.initial_status(type, target)

          SocialStore.insert_follow(context, %{
            user_id: user_id,
            target_type: type,
            target_id: target_id,
            status: status,
            accepted_at: if(status == "active" and type == "user", do: DateTime.utc_now())
          })
          |> case do
            {:ok, follow} -> {:ok, follow, :created}
            error -> error
          end

        follow ->
          {:ok, follow, :existing}
      end
    end
  end

  def unfollow(%{user_id: user_id} = context, type, target_id),
    do: SocialStore.delete_follow(context, user_id, type, target_id)

  def status(%{user_id: user_id} = context, type, target_id),
    do: context |> SocialStore.get_follow(user_id, type, target_id) |> FollowPolicy.status()

  @doc "The person accepts a request that targets them."
  def accept(%{user_id: user_id} = context, follow_id, now) do
    case incoming(context, follow_id, user_id) do
      %{status: "requested"} = follow -> SocialStore.accept_follow(context, follow.id, now)
      _missing -> {:error, :not_found}
    end
  end

  @doc "ADR-193 §2: a person who goes public accepts every request waiting for them."
  def accept_all(%{user_id: user_id} = context, now),
    do: SocialStore.accept_all_incoming(context, user_id, now)

  @doc "The person declines a request, or removes someone who follows them."
  def remove_incoming(%{user_id: user_id} = context, follow_id) do
    case incoming(context, follow_id, user_id) do
      nil -> {:error, :not_found}
      follow -> with :ok <- SocialStore.delete_follow_by_id(context, follow.id), do: {:ok, follow}
    end
  end

  defp incoming(context, follow_id, user_id) do
    case SocialStore.get_follow_by_id(context, follow_id) do
      %{target_type: "user", target_id: ^user_id} = follow -> follow
      _other -> nil
    end
  end
end
