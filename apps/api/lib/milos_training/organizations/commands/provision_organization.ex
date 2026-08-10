defmodule MilosTraining.Organizations.Commands.ProvisionOrganization do
  alias MilosTraining.Organizations.Domain.{InvitationToken, MembershipPolicy}
  alias MilosTraining.Organizations.{OrganizationStore, PlatformContext}

  def call(%PlatformContext{} = context, params, issued_at) do
    with {:ok, owner_email} <- require_owner_email(value(params, :initial_owner_email)),
         true <- :owner in MembershipPolicy.roles() do
      token = InvitationToken.generate()
      lifetime = value(params, :invitation_lifetime_seconds) || 604_800

      invitation_params = %{
        token_digest: InvitationToken.digest(token),
        role: :owner,
        expires_at: DateTime.add(issued_at, lifetime, :second),
        intended_email_digest: intended_email_digest(owner_email)
      }

      with {:ok, result} <-
             OrganizationStore.provision_organization(
               params,
               invitation_params,
               context.user_id,
               issued_at
             ) do
        {:ok, Map.put(result, :initial_owner_token, token)}
      end
    else
      false -> {:error, :owner_role_unavailable}
      error -> error
    end
  end

  def call(_context, _params, _issued_at), do: {:error, :vendor_required}

  # Provisioning is how an invitation goes out; an organization with no one
  # to invite has no way for anyone but the vendor to ever access it.
  defp require_owner_email(nil), do: {:error, :owner_email_required}
  defp require_owner_email(""), do: {:error, :owner_email_required}

  defp require_owner_email(email) when is_binary(email) do
    case String.trim(email) do
      "" -> {:error, :owner_email_required}
      trimmed -> {:ok, trimmed}
    end
  end

  defp require_owner_email(_email), do: {:error, :owner_email_required}

  defp intended_email_digest(email) do
    email |> String.trim() |> String.downcase() |> then(&:crypto.hash(:sha256, &1))
  end

  defp value(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end
