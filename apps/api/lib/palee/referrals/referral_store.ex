defmodule Palee.Referrals.ReferralStore do
  @moduledoc "Facade over the referrals adapter (ADR-156); every call runs in the caller's session."

  @behaviour Palee.Referrals.Ports.ReferralStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :referral_store)

  defp call(context, function, args),
    do: RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)

  @impl true
  def get_active_code(context, user_id), do: call(context, :get_active_code, [user_id])

  @impl true
  def insert_code(context, attrs), do: call(context, :insert_code, [attrs])

  @impl true
  def revoke_code(context, code, at), do: call(context, :revoke_code, [code, at])

  @impl true
  def resolve_code(code), do: adapter().resolve_code(code)

  @impl true
  def get_attribution(context, id), do: call(context, :get_attribution, [id])

  @impl true
  def get_attribution_for(context, user_id), do: call(context, :get_attribution_for, [user_id])

  @impl true
  def insert_attribution(context, attrs), do: call(context, :insert_attribution, [attrs])

  @impl true
  def replace_attribution(context, attribution, attrs),
    do: call(context, :replace_attribution, [attribution, attrs])

  @impl true
  def update_attribution(context, attribution, changes),
    do: call(context, :update_attribution, [attribution, changes])

  @impl true
  def list_attributions(context, filters), do: call(context, :list_attributions, [filters])

  @impl true
  def stats(context, since), do: call(context, :stats, [since])

  @impl true
  def with_friend_lock(context, user_id, fun),
    do: call(context, :with_friend_lock, [user_id, fun])
end
