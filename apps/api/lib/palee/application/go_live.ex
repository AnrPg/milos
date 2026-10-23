defmodule Palee.Application.GoLive do
  @moduledoc """
  ADR-184: the application-level entry to `Organizations.go_live/3`
  (`GoLivePolicy`) for the commands that need facts about the people
  involved: whether someone is the business's staff or one of its mock
  people. The facts are read only when the business is gated, so active
  businesses pay nothing.
  """

  alias Palee.{BusinessAccounts, Organizations}

  @staff_roles [:owner, :admin, :coach, :front_desk, :accountant, :janitor]

  @doc "A going-live action that needs no facts (publish, invite, send)."
  def check(context, action), do: Organizations.go_live(context, action)

  @doc "The same for a business known only by id."
  def check_at(organization_id, action) when is_binary(organization_id),
    do: Organizations.go_live(Organizations.get_by_id(organization_id), action)

  @doc "A booking, trial, appointment or event place taken by `user_id`."
  def check_booking(context, user_id) do
    gated(context, :take_booking, fn ->
      %{
        actor_staff?: Organizations.staff_member?(context, user_id),
        actor_demo_person?: BusinessAccounts.demo_person?(context, user_id)
      }
    end)
  end

  @doc """
  The same for a place taken at a business known only by id (an open event
  reached by its link).
  """
  def check_booking_at(organization_id, user_id) when is_binary(organization_id) do
    case Organizations.get_by_id(organization_id) do
      nil ->
        :ok

      organization ->
        check_booking(
          %{organization: organization, organization_id: organization_id, user_id: user_id},
          user_id
        )
    end
  end

  @doc "Giving `roles` to `user_id`: staff roles go only to mock people or oneself."
  def check_role_grant(context, user_id, roles) do
    if Enum.any?(List.wrap(roles), &(staff_role(&1) in @staff_roles)) do
      gated(context, :grant_staff_role, fn ->
        %{
          target_self?: Map.get(context, :user_id) == user_id,
          target_demo_person?: BusinessAccounts.demo_person?(context, user_id)
        }
      end)
    else
      :ok
    end
  end

  @doc "An invoice or a payment for `user_id`."
  def check_payment(context, user_id) do
    gated(context, :take_payment, fn ->
      %{payer_demo_person?: BusinessAccounts.demo_person?(context, user_id)}
    end)
  end

  defp gated(context, action, facts) do
    if Organizations.business_gated?(context),
      do: Organizations.go_live(context, action, facts.()),
      else: :ok
  end

  defp staff_role(role) when is_atom(role), do: role

  defp staff_role(role) when is_binary(role) do
    Enum.find(@staff_roles, &(Atom.to_string(&1) == role))
  end

  defp staff_role(_role), do: nil
end
