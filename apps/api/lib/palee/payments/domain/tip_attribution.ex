defmodule Palee.Payments.Domain.TipAttribution do
  @moduledoc """
  ADR-272: whose tip it is. The card provider does not say which staff
  member a tip is for, so Palee decides from how the payment started:

    * started on a staff member's phone (Tap to Pay): the person who
      started it (`started_payment`);
    * otherwise (a payment started at the desk, or with no starter on
      record) the front desk: the box's only front desk person when there
      is exactly one (`sole_front_desk`), else the front desk role,
      unpersonalised (`front_desk_role`).

  Owners and admins are never counted as front desk, even when they also
  hold the front desk role. Pure: the caller passes the box's roles.
  """

  @attributions ~w(started_payment sole_front_desk front_desk_role)

  def attributions, do: @attributions

  @doc """
  The attribution of `intent`'s tip as changes to write on it, or nil when
  there is no tip or it is already attributed. `roles_by_user`: the box's
  people, `%{user_id => roles}`.
  """
  def attribute(intent, roles_by_user) do
    cond do
      (intent[:tip_cents] || 0) <= 0 -> nil
      is_binary(intent[:tip_attribution]) -> nil
      started_on_phone?(intent) -> person(intent.created_by_id, "started_payment")
      true -> front_desk(roles_by_user)
    end
  end

  @doc "Where a payment started: `phone` (the default for Tap to Pay) or `desk`."
  def started_on(intent) do
    case (intent[:metadata] || %{})["started_on"] do
      "desk" -> "desk"
      _phone -> "phone"
    end
  end

  defp started_on_phone?(intent),
    do: is_binary(intent[:created_by_id]) and started_on(intent) == "phone"

  defp front_desk(roles_by_user) do
    case front_desk_people(roles_by_user) do
      [only] -> person(only, "sole_front_desk")
      _none_or_many -> %{tip_attribution: "front_desk_role", tip_recipient_role: "front_desk"}
    end
  end

  @doc "The box's front desk people: the front desk role, without owner or admin."
  def front_desk_people(roles_by_user) do
    roles_by_user
    |> Enum.filter(fn {_user_id, roles} ->
      roles = Enum.map(List.wrap(roles), &to_string/1)
      "front_desk" in roles and not Enum.any?(roles, &(&1 in ["owner", "admin"]))
    end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
  end

  defp person(user_id, attribution),
    do: %{tip_attribution: attribution, tip_recipient_user_id: user_id}
end
