defmodule MilosTraining.Finance.Domain.ReferralPolicy do
  def validate_event(
        %{
          referrer_user_id: referrer_user_id,
          referred_user_id: referred_user_id,
          membership_user_id: membership_user_id
        } = event
      ) do
    referrer_role = Map.get(event, :referrer_role) || Map.get(event, "referrer_role")
    referred_role = Map.get(event, :referred_role) || Map.get(event, "referred_role")

    cond do
      blank?(referrer_user_id) or blank?(referred_user_id) ->
        :ok

      referrer_user_id == referred_user_id ->
        {:error, :self_referral_not_allowed}

      blank?(membership_user_id) ->
        {:error, :referral_membership_required}

      membership_user_id && membership_user_id != referred_user_id ->
        {:error, :referral_membership_user_mismatch}

      not eligible_participant_role?(referrer_role) ->
        {:error, :referral_referrer_role_ineligible}

      not eligible_participant_role?(referred_role) ->
        {:error, :referral_referred_role_ineligible}

      true ->
        :ok
    end
  end

  def validate_reward_creation(event_status, existing_reward?) do
    cond do
      event_status not in ["approved", "applied"] ->
        {:error, :referral_event_not_approved}

      existing_reward? ->
        {:error, :referral_reward_already_exists}

      true ->
        :ok
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false

  defp eligible_participant_role?(role) when role in [:member, :athlete, "member", "athlete"],
    do: true

  defp eligible_participant_role?(_role), do: false
end
