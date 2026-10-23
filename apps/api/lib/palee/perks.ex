defmodule Palee.Perks do
  @moduledoc """
  The Perks bounded context (ADR-191): deals a gym or an independent coach
  publishes for its clients at partner businesses («10% στο SupplementsX με
  τον κωδικό COACHNIKOS», a QR shown at the counter). It owns the perk, its
  pool of single-use codes and each member's claim and use.

  Every function runs in the caller's scope: the business's
  (`organization_id`, with the member's `user_id` when a member acts).
  Use cases live in `Palee.Application.Perks` (staff),
  `Palee.Application.MemberPerks` (members, and the billing slot) and
  `Palee.Application.PerkVerification` (the partner's link).
  """

  alias Palee.Perks.{Perk, PerkCode, PerkStore}
  alias Palee.Perks.Domain.{PerkRules, TenantDataPolicy, VerificationToken}

  defdelegate create_perk(context, attrs), to: PerkStore
  defdelegate update_perk(context, perk, attrs), to: PerkStore
  defdelegate delete_perk(context, perk), to: PerkStore
  defdelegate get_perk(context, id), to: PerkStore
  defdelegate list_perks(context, filters \\ %{}), to: PerkStore
  defdelegate code_stats(context, perk_ids), to: PerkStore
  defdelegate claim(context, perk_id, user_id, decide), to: PerkStore
  defdelegate use_claim(context, claim_id, via, actor_id, at, check), to: PerkStore
  defdelegate revoke_claim(context, claim_id, actor_id, at), to: PerkStore
  defdelegate rotate_token(context, claim_id, user_id, token_hash), to: PerkStore
  defdelegate get_claim(context, id), to: PerkStore
  defdelegate list_member_claims(context, user_id), to: PerkStore
  defdelegate list_claims(context, perk_id, opts \\ %{}), to: PerkStore
  defdelegate member_package_ids(context, user_id, today), to: PerkStore

  @doc "Moves a perk one lifecycle step (`:publish`, `:pause`, `:expire`) and writes it."
  def transition(context, %Perk{} = perk, step, now, today) do
    with {:ok, changes} <- PerkRules.transition(perk, step, now, today) do
      PerkStore.set_status(context, perk, Map.put(changes, :updated_by_id, context[:user_id]))
    end
  end

  @doc "Adds normalised codes to a perk's pool."
  def add_codes(context, perk_id, codes) do
    with {:ok, codes} <- PerkCode.normalize_all(codes),
         do: PerkStore.add_codes(context, perk_id, codes)
  end

  def editable_fields, do: Perk.editable_fields()
  def max_codes, do: PerkCode.max_codes()

  defdelegate benefit_types(), to: PerkRules
  defdelegate methods(), to: PerkRules
  defdelegate statuses(), to: PerkRules
  defdelegate audiences(), to: PerkRules
  defdelegate claim_statuses(), to: PerkRules
  defdelegate effective_status(perk, today), to: PerkRules
  defdelegate live?(perk, today), to: PerkRules
  defdelegate check_update(perk, changes, today), to: PerkRules
  defdelegate for_member?(perk, facts), to: PerkRules
  defdelegate claim_check(perk, facts), to: PerkRules
  defdelegate usable?(perk, claim, today), to: PerkRules
  defdelegate remaining(perk), to: PerkRules
  defdelegate benefit_label(perk), to: PerkRules

  defdelegate new_secret(), to: VerificationToken
  defdelegate token_matches?(stored_hash, nonce), to: VerificationToken, as: :matches?
  defdelegate link_expires_at(now, valid_until), to: VerificationToken, as: :expires_at
  defdelegate link_payload(claim_id, organization_id, nonce, expires_at), to: VerificationToken, as: :payload
  defdelegate parse_link(payload, now), to: VerificationToken, as: :parse
  defdelegate link_max_seconds(), to: VerificationToken, as: :max_seconds
  defdelegate display_code(), to: VerificationToken

  # Tenant data lifecycle (ADR-117).
  def tenant_data_policy, do: TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end
