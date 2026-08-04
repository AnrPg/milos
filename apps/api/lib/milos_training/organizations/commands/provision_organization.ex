defmodule MilosTraining.Organizations.Commands.ProvisionOrganization do
  alias MilosTraining.Organizations.Domain.{InvitationToken, MembershipPolicy}
  alias MilosTraining.Organizations.{OrganizationStore, PlatformContext}

  def call(%PlatformContext{} = context, params, issued_at) do
    token = InvitationToken.generate()
    lifetime = value(params, :invitation_lifetime_seconds) || 604_800

    invitation_params = %{
      token_digest: InvitationToken.digest(token),
      role: :owner,
      expires_at: DateTime.add(issued_at, lifetime, :second),
      intended_email_digest: intended_email_digest(value(params, :initial_owner_email))
    }

    with true <- :owner in MembershipPolicy.roles(),
         {:ok, result} <-
           OrganizationStore.provision_organization(
             params,
             invitation_params,
             context.user_id,
             issued_at
           ) do
      {:ok, Map.put(result, :initial_owner_token, token)}
    else
      false -> {:error, :owner_role_unavailable}
      error -> error
    end
  end

  def call(_context, _params, _issued_at), do: {:error, :platform_owner_required}

  defp intended_email_digest(nil), do: nil
  defp intended_email_digest(""), do: nil

  defp intended_email_digest(email) do
    email |> String.trim() |> String.downcase() |> then(&:crypto.hash(:sha256, &1))
  end

  defp value(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end
