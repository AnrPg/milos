defmodule Palee.Application.RegisterInvitedUser do
  alias Palee.Application.{
    InvitationAccountRole,
    ManageCoachingRelationships,
    RegisterProfile,
    TokenIssuer
  }

  alias Palee.Organizations.Domain.MembershipPolicy
  alias Palee.{Identity, Organizations}

  def call(params, allowed_roles \\ MembershipPolicy.roles())
      when is_map(params) and is_list(allowed_roles) do
    token = value(params, :invitation_token)

    with {:ok, invitation} <- Organizations.inspect_invitation(token),
         :ok <- authorize_role(invitation.role, allowed_roles),
         account_role = InvitationAccountRole.for_invitation(invitation.role),
         {:ok, user} <- RegisterProfile.call(registration_params(params, account_role)),
         {:ok, redemption} <- redeem_or_cleanup(token, user),
         :ok <- start_invited_coaching(redemption, user),
         {:ok, user} <- align_account_role(user, account_role),
         {:ok, tokens} <- TokenIssuer.issue_pair(user) do
      {:ok,
       tokens
       |> Map.put(:user, user)
       |> Map.put(:organization, redemption.organization)
       |> Map.put(:membership, redemption.membership)
       |> Map.put(:invitation, invitation)}
    end
  end

  defp authorize_role(role, allowed_roles) do
    if role in allowed_roles, do: :ok, else: {:error, :invalid_invitation}
  end

  defp registration_params(params, account_role) do
    %{
      handle: value(params, :handle) || value(params, :nickname),
      display_name: value(params, :display_name),
      password: value(params, :password),
      role: self_registration_role(account_role),
      # Carried through so an email-bound invitation can be matched against the
      # account being created in this same request (F-10).
      email: value(params, :email)
    }
    |> maybe_put(:preferred_locale, value(params, :preferred_locale))
  end

  defp start_invited_coaching(%{invitation: invitation, organization: organization}, user),
    do: ManageCoachingRelationships.start_invited(organization.id, invitation, user.id)

  defp self_registration_role(:athlete), do: :athlete
  defp self_registration_role(_role), do: :member

  defp align_account_role(user, role) do
    if user.role == role, do: {:ok, user}, else: Identity.update_role(user, role)
  end

  defp redeem_or_cleanup(token, user) do
    case Organizations.redeem_invitation(token, user.id) do
      {:ok, redemption} ->
        {:ok, redemption}

      {:error, reason} ->
        case Identity.delete(user) do
          :ok -> {:error, reason}
          {:error, _cleanup_reason} -> {:error, :registration_cleanup_failed}
        end
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp value(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end
