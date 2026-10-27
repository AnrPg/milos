defmodule Palee.Application.AcceptInvitation do
  @moduledoc """
  ADR-204: the signed-in profile accepts an organization invitation itself,
  instead of creating a new profile through the invitation's sign-up form.

  Same redemption as `RedeemRegistrationInvitation` (email binding, demo
  businesses, coaching start), plus the account surface role the invited
  sign-up would get: a staff invitation lifts a member or athlete profile to
  the staff shell. A role change revokes the profile's sessions, so a fresh
  token pair comes back with it; without a change the session stays as it is.
  """
  alias Palee.Application.{InvitationAccountRole, RedeemRegistrationInvitation, TokenIssuer}
  alias Palee.{Identity, Organizations}

  def call(user, token, allowed_roles \\ Organizations.roles())
      when is_binary(token) and is_list(allowed_roles) do
    with {:ok, invitation} <- Organizations.inspect_invitation(token),
         :ok <- authorize_role(invitation.role, allowed_roles),
         {:ok, redemption} <- RedeemRegistrationInvitation.call(user, token),
         {:ok, updated, changed?} <- promote(user, invitation.role),
         {:ok, tokens} <- session_for(updated, changed?) do
      {:ok, %{redemption: redemption, user: updated, tokens: tokens}}
    end
  end

  defp authorize_role(role, allowed_roles) do
    if role in allowed_roles, do: :ok, else: {:error, :invalid_invitation}
  end

  defp promote(user, invitation_role) do
    target = InvitationAccountRole.for_invitation(invitation_role)

    if InvitationAccountRole.promotes?(user.role, target) do
      case Identity.update_role(user, target) do
        {:ok, updated} -> {:ok, updated, true}
        error -> error
      end
    else
      {:ok, user, false}
    end
  end

  defp session_for(_user, false), do: {:ok, nil}
  defp session_for(user, true), do: TokenIssuer.issue_pair(user)
end
