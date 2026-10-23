defmodule Palee.Perks.PerkStore do
  @moduledoc "Facade over the perks adapter (ADR-191); every call runs in the caller's session."

  @behaviour Palee.Perks.Ports.PerkStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :perk_store)

  defp call(context, function, args),
    do: RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)

  @impl true
  def create_perk(context, attrs), do: call(context, :create_perk, [attrs])

  @impl true
  def update_perk(context, perk, attrs), do: call(context, :update_perk, [perk, attrs])

  @impl true
  def set_status(context, perk, changes), do: call(context, :set_status, [perk, changes])

  @impl true
  def delete_perk(context, perk), do: call(context, :delete_perk, [perk])

  @impl true
  def get_perk(context, id), do: call(context, :get_perk, [id])

  @impl true
  def list_perks(context, filters), do: call(context, :list_perks, [filters])

  @impl true
  def add_codes(context, perk_id, codes), do: call(context, :add_codes, [perk_id, codes])

  @impl true
  def code_stats(context, perk_ids), do: call(context, :code_stats, [perk_ids])

  @impl true
  def claim(context, perk_id, user_id, decide),
    do: call(context, :claim, [perk_id, user_id, decide])

  @impl true
  def use_claim(context, claim_id, via, actor_id, at, check),
    do: call(context, :use_claim, [claim_id, via, actor_id, at, check])

  @impl true
  def revoke_claim(context, claim_id, actor_id, at),
    do: call(context, :revoke_claim, [claim_id, actor_id, at])

  @impl true
  def rotate_token(context, claim_id, user_id, token_hash),
    do: call(context, :rotate_token, [claim_id, user_id, token_hash])

  @impl true
  def get_claim(context, id), do: call(context, :get_claim, [id])

  @impl true
  def list_member_claims(context, user_id), do: call(context, :list_member_claims, [user_id])

  @impl true
  def list_claims(context, perk_id, opts), do: call(context, :list_claims, [perk_id, opts])

  @impl true
  def member_package_ids(context, user_id, today),
    do: call(context, :member_package_ids, [user_id, today])
end
