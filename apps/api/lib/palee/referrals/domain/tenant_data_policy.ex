defmodule Palee.Referrals.Domain.TenantDataPolicy do
  @moduledoc """
  Referrals tenant data retention and purge policy (ADR-117, ADR-156).

  Invite codes and the invite funnel are operational data with no retention
  obligation of their own; what has accounting weight (the referral event,
  its reward and any credit) lives in Finance. Purged before Finance because
  an invite points at a referral programme and a referral event.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "referrals",
            purge_order: 89,
            disposition: :purge,
            basis:
              "Invite codes and the invite funnel are operational data; the accounting record (referral event, reward, credit) is Finance's. Purged before Finance because invites reference its programmes and events.",
            tables: [
              %{table: "referral_attributions"},
              %{table: "referral_codes"}
            ]
          })

  def policy, do: @policy
end
