defmodule MilosTraining.Application.RegisterInvitedUser do
  alias MilosTraining.Application.TokenIssuer
  alias MilosTraining.{Identity, Organizations}

  def call(params, allowed_roles \\ [:owner, :admin, :coach, :member, :athlete])
      when is_map(params) and is_list(allowed_roles) do
    token = value(params, :invitation_token)

    with {:ok, invitation} <- Organizations.inspect_invitation(token),
         :ok <- authorize_role(invitation.role, allowed_roles),
         {:ok, user} <- Identity.register(registration_params(params)),
         {:ok, redemption} <- redeem_or_cleanup(token, user),
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

  defp registration_params(params) do
    %{
      nickname: value(params, :nickname),
      password: value(params, :password),
      role: :member,
      # Carried through so an email-bound invitation can be matched against the
      # account being created in this same request (F-10).
      email: value(params, :email)
    }
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

  defp value(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end
