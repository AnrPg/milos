defmodule Palee.Application.MembershipRenewal do
  @moduledoc """
  ADR-220: the member decides whether their subscription renews, and can
  leave the box; staff can do both for them and mark someone as left.

  Turning renewal off (or leaving) never takes away a paid period: the
  subscription runs to its last day and then ends through the usual expiry
  flow. Only unpaid invoices for periods after that day (or for packages
  that never started) are voided; anything already used stays owed and
  keeps its payment reminders until it is paid. Staff who manage
  billing hear when a member leaves.
  """

  alias Palee.{Finance, Identity, Notifications}
  alias Palee.Application.RevokeAccess

  @doc "The member turns renewal of one of their subscriptions on or off."
  def member_set_auto_renew(%{user_id: user_id} = context, subscription_id, auto_renew)
      when is_boolean(auto_renew),
      do:
        Finance.set_subscription_auto_renew(
          context,
          user_id,
          subscription_id,
          auto_renew,
          "member"
        )

  def member_set_auto_renew(_context, _subscription_id, _auto_renew),
    do: {:error, :invalid_auto_renew}

  @doc "The member leaves the box: they keep everything they paid for."
  def member_leave(%{user_id: user_id} = context, params) do
    with {:ok, result} <-
           Finance.leave_membership(context, user_id, %{
             "by" => "member",
             "reason" => reason(params)
           }) do
      notify_staff(context, user_id, result)
      {:ok, result}
    end
  end

  @doc "The member changes their mind before their last day."
  def member_stay(%{user_id: user_id} = context),
    do: Finance.undo_leave_membership(context, user_id, "member")

  @doc "Staff turn a member's renewal on or off (for example, asked at the desk)."
  def staff_set_auto_renew(context, user_id, subscription_id, auto_renew)
      when is_boolean(auto_renew),
      do:
        Finance.set_subscription_auto_renew(
          context,
          user_id,
          subscription_id,
          auto_renew,
          "staff"
        )

  def staff_set_auto_renew(_context, _user_id, _subscription_id, _auto_renew),
    do: {:error, :invalid_auto_renew}

  @doc """
  Staff mark a member as left: on a day they choose, today at the earliest
  (none: when what they paid for ends). What was already used stays owed.
  """
  def staff_mark_left(context, user_id, params) when is_map(params) do
    with {:ok, result} <-
           Finance.leave_membership(context, user_id, %{
             "by" => "staff",
             "reason" => reason(params),
             "leaving_on" => Map.get(params, "leaving_on"),
             "commitment_override_reason" => Map.get(params, "commitment_override_reason")
           }) do
      # Gone today: access ends now, so their upcoming bookings go as well
      # (the daily expiry run would not see this change any more).
      if result.membership.status == "cancelled",
        do:
          RevokeAccess.call(context, %{
            user_id: user_id,
            membership_id: result.membership.id,
            status: "cancelled"
          })

      {:ok, result}
    end
  end

  @doc "Staff undo a leave (the member came back or it was a mistake)."
  def staff_undo_leave(context, user_id),
    do: Finance.undo_leave_membership(context, user_id, "staff")

  @doc "The day a member leaving today would keep access until, or nil."
  def leave_preview(%{user_id: user_id} = context),
    do: Finance.membership_leave_preview(context, user_id)

  defp notify_staff(%{organization_id: organization_id}, user_id, result) do
    person = Identity.find_by_id(user_id)
    membership = result.membership

    Notifications.dispatch_event(:member_leaving, %{
      organization_id: organization_id,
      member_user_id: user_id,
      person_nickname: person && person.nickname,
      leaving_on: Date.to_iso8601(result.leaving_on),
      reason: membership.leave_reason,
      left_at: DateTime.to_unix(membership.left_at, :microsecond)
    })
  end

  defp reason(params) when is_map(params) do
    case Map.get(params, "reason") do
      value when is_binary(value) -> String.slice(value, 0, 500)
      _other -> nil
    end
  end

  defp reason(_params), do: nil
end
