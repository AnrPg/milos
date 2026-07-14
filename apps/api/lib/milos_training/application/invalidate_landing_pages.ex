defmodule MilosTraining.Application.InvalidateLandingPages do
  alias MilosTraining.Application.BroadcastUserSync
  alias MilosTraining.Identity
  alias MilosTraining.Infrastructure.Cache.LandingCache

  def for_user(user_id) do
    for_users([user_id])
  end

  def for_users(user_ids) when is_list(user_ids) do
    deduped_user_ids =
      user_ids
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    LandingCache.batch_invalidate(deduped_user_ids)
    BroadcastUserSync.for_users(deduped_user_ids, ["landing"], reason: "landing_invalidated")
  end

  def for_all_users do
    user_ids =
      Identity.list_all_users()
      |> Enum.map(& &1.id)

    for_users(user_ids)
  end
end
