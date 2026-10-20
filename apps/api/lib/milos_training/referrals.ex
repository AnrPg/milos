defmodule MilosTraining.Referrals do
  @moduledoc """
  The Referrals bounded context (ADR-156, P2-M8): members bring friends.
  It owns each member's invite code at a box and the invite funnel of each
  friend, from the first invite to the first payment. Finance owns the
  programme, the referral the admin approves and the reward; this context
  opens that referral when an invite qualifies.

  Every function runs in the caller's scope: the box's for its invites, the
  person's (`%{user_id: ...}`) for their own.
  """

  alias MilosTraining.Referrals.{ReferralAttribution, ReferralStore}
  alias MilosTraining.Referrals.Domain.{Attribution, Code}

  defdelegate get_active_code(context, user_id), to: ReferralStore
  defdelegate insert_code(context, attrs), to: ReferralStore
  defdelegate revoke_code(context, code, at), to: ReferralStore
  defdelegate get_attribution(context, id), to: ReferralStore
  defdelegate get_attribution_for(context, user_id), to: ReferralStore
  defdelegate insert_attribution(context, attrs), to: ReferralStore
  defdelegate replace_attribution(context, attribution, attrs), to: ReferralStore
  defdelegate update_attribution(context, attribution, changes), to: ReferralStore
  defdelegate list_attributions(context, filters), to: ReferralStore
  defdelegate stats(context, since), to: ReferralStore
  defdelegate with_friend_lock(context, user_id, fun), to: ReferralStore

  @doc "Who a code someone typed, scanned or clicked belongs to, or nil."
  def resolve_code(input) do
    case Code.normalize(input) do
      {:ok, code} -> ReferralStore.resolve_code(code)
      :error -> nil
    end
  end

  defdelegate generate_code(), to: Code, as: :generate
  defdelegate normalize_code(input), to: Code, as: :normalize
  defdelegate claim_check(facts), to: Attribution, as: :claim
  defdelegate expires_at(now, days), to: Attribution
  defdelegate stage(attribution), to: Attribution
  defdelegate qualifies?(attribution, program), to: Attribution
  defdelegate cap_reached?(count, cap), to: Attribution
  defdelegate channels(), to: Attribution
  defdelegate statuses(), to: Attribution

  @doc "Moves an invite one funnel step and writes it; `:noop` when nothing changes."
  def advance(context, %ReferralAttribution{} = attribution, step, at) do
    case Attribution.advance(attribution, step, at) do
      {:ok, changes} -> ReferralStore.update_attribution(context, attribution, changes)
      {:expire, changes} -> ReferralStore.update_attribution(context, attribution, changes)
      :noop -> :noop
    end
  end

  @doc "Gives an invite to another member (staff, board 11 Q4)."
  def reassign(context, %ReferralAttribution{} = attribution, new_referrer_id, actor_id, note, at) do
    with {:ok, changes} <-
           Attribution.reassign(attribution, new_referrer_id, actor_id, note, at) do
      ReferralStore.update_attribution(context, attribution, changes)
    end
  end

  def tenant_data_policy, do: MilosTraining.Referrals.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: MilosTraining.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: MilosTraining.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: MilosTraining.TenantData.TableStore.purge(tenant_data_policy(), context)
end
