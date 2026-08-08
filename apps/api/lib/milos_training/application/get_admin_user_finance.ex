defmodule MilosTraining.Application.GetAdminUserFinance do
  @moduledoc false

  alias MilosTraining.Application.GetFinanceMemberProfile
  alias MilosTraining.Application.TenantUserAccess
  alias MilosTraining.{Finance, Identity}
  alias MilosTraining.Identity.Domain.AdminProfilePolicy
  alias MilosTraining.Organizations.Domain.AdminPath

  def call(user_id, tenant_context, organization_slug \\ nil) do
    with {:ok, user} <- TenantUserAccess.fetch_active_user(tenant_context, user_id) do
      if AdminProfilePolicy.finance_available?(user.role) do
        with {:ok, profile} <- GetFinanceMemberProfile.call(user_id, tenant_context) do
          entitlement = Finance.get_effective_entitlement(tenant_context, user_id)
          details = finance_details(tenant_context, profile, user_id)

          {:ok,
           %{
             user_id: user_id,
             available: true,
             summary: %{
               credit_balance: profile.credit_balance,
               current_status: profile.drill_down.current_status,
               package_relationship: profile.drill_down.package_relationship,
               outstanding_items: profile.drill_down.outstanding_items,
               effective_entitlement: entitlement
             },
             details: details,
             drill_down: profile.drill_down,
             operational_links: %{
               workspace: AdminPath.admin_url("/admin/finance", organization_slug),
               member: AdminPath.admin_url("/admin/finance?member=#{user_id}", organization_slug)
             }
           }}
        end
      else
        {:ok,
         %{
           user_id: user_id,
           available: false,
           summary: nil,
           details: empty_details(),
           drill_down: nil,
           operational_links: %{}
         }}
      end
    end
  end

  defp finance_details(tenant_context, profile, user_id) do
    events = Finance.list_referral_events(tenant_context)
    rewards = Finance.list_referral_rewards(tenant_context)

    %{
      membership: serialize_membership(profile.membership),
      package_subscriptions: Enum.map(profile.package_subscriptions, &serialize_subscription/1),
      referral_claims:
        events
        |> Enum.filter(&(&1.referred_user_id == user_id))
        |> Enum.map(&serialize_referral(&1, :referrer_user_id, :referrer_nickname)),
      referred_members:
        events
        |> Enum.filter(&(&1.referrer_user_id == user_id))
        |> Enum.map(&serialize_referral(&1, :referred_user_id, :referred_nickname)),
      referral_rewards:
        rewards
        |> Enum.filter(&(&1.recipient_user_id == user_id))
        |> Enum.map(&serialize_reward/1)
    }
  end

  defp empty_details do
    %{
      membership: nil,
      package_subscriptions: [],
      referral_claims: [],
      referred_members: [],
      referral_rewards: []
    }
  end

  defp serialize_membership(nil), do: nil

  defp serialize_membership(membership) do
    Map.take(membership, [
      :id,
      :user_id,
      :status,
      :user_type_snapshot,
      :signup_source,
      :starts_on,
      :expires_on,
      :entitlement_status,
      :entitlement_source,
      :notes
    ])
  end

  defp serialize_subscription(subscription) do
    Map.take(subscription, [
      :id,
      :membership_package_id,
      :package_code_snapshot,
      :package_family_snapshot,
      :billing_period_snapshot,
      :price_cents_snapshot,
      :status,
      :starts_on,
      :ends_on
    ])
  end

  defp serialize_referral(event, related_user_key, nickname_key) do
    related_user_id = Map.fetch!(event, related_user_key)
    related_user = Identity.find_by_id(related_user_id)

    event
    |> Map.take([
      :id,
      :referral_program_id,
      :referrer_user_id,
      :referred_user_id,
      :membership_id,
      :status,
      :signup_source_snapshot,
      :notes,
      :inserted_at
    ])
    |> Map.put(nickname_key, related_user && related_user.nickname)
  end

  defp serialize_reward(reward) do
    Map.take(reward, [
      :id,
      :referral_event_id,
      :recipient_user_id,
      :membership_id,
      :reward_type,
      :reward_value,
      :status,
      :applied_at,
      :inserted_at
    ])
  end
end
