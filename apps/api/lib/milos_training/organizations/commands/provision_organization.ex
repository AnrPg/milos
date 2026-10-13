defmodule MilosTraining.Organizations.Commands.ProvisionOrganization do
  alias MilosTraining.Organizations.Domain.{InvitationToken, MembershipPolicy}
  alias MilosTraining.Organizations.{OrganizationStore, PlatformContext}
  alias MilosTraining.Organizations.Commands.SeedTenantDefaults

  @doc """
  Provisions the organization, its settings, the initial admin invitation and
  the audit event, then runs `opts[:seed_defaults]` in the new organization's
  tenant scope - all in one transaction (ADR-133). `opts[:issued_at]` pins the
  invitation clock.
  """
  def call(context, params, opts \\ [])

  def call(%PlatformContext{} = context, params, opts) do
    issued_at = Keyword.get(opts, :issued_at, DateTime.utc_now())
    seed_defaults = SeedTenantDefaults.seed_option(opts)

    with {:ok, owner_email} <- require_owner_email(value(params, :initial_owner_email)),
         true <- :admin in MembershipPolicy.roles() do
      token = InvitationToken.generate()
      lifetime = value(params, :invitation_lifetime_seconds) || 604_800

      invitation_params = %{
        token_digest: InvitationToken.digest(token),
        role: :admin,
        expires_at: DateTime.add(issued_at, lifetime, :second),
        intended_email_digest: intended_email_digest(owner_email)
      }

      # The organization row is a system insert (there is no tenant session
      # yet); the seeded defaults are written in the new organization's scope.
      OrganizationStore.transaction(fn ->
        with {:ok, result} <-
               OrganizationStore.provision_organization(
                 params,
                 invitation_params,
                 context.user_id,
                 issued_at
               ),
             {:ok, _defaults} <-
               SeedTenantDefaults.run(result.organization.id, context.user_id, seed_defaults) do
          {:ok, Map.put(result, :initial_owner_token, token)}
        end
      end)
    else
      false -> {:error, :admin_role_unavailable}
      error -> error
    end
  end

  def call(_context, _params, _opts), do: {:error, :vendor_required}

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
