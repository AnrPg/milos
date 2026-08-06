defmodule MilosTraining.Organizations.Commands.IssuePlatformInvitation do
  alias MilosTraining.Organizations.Domain.{InvitationToken, MembershipPolicy}
  alias MilosTraining.Organizations.{OrganizationStore, PlatformContext}

  @default_lifetime_seconds 604_800

  def call(%PlatformContext{} = context, organization_id, params, issued_at)
      when is_binary(organization_id) do
    token = InvitationToken.generate()
    lifetime = value(params, :lifetime_seconds) || @default_lifetime_seconds
    role = normalize_role(value(params, :role))

    with organization when not is_nil(organization) <-
           OrganizationStore.get_organization_by_id(organization_id),
         true <- role in MembershipPolicy.roles(),
         {:ok, invitation} <-
           OrganizationStore.issue_invitation(
             %{
               organization_id: organization.id,
               token_digest: InvitationToken.digest(token),
               role: role,
               expires_at: DateTime.add(issued_at, lifetime, :second),
               issued_by_user_id: context.user_id,
               intended_email_digest: intended_email_digest(value(params, :intended_email))
             },
             issued_at
           ) do
      {:ok, %{invitation: invitation, organization: organization, token: token}}
    else
      nil -> {:error, :not_found}
      false -> {:error, [role: "is invalid"]}
      error -> error
    end
  end

  def call(%PlatformContext{}, _organization_id, _params, _issued_at), do: {:error, :not_found}

  def call(_context, _organization_id, _params, _issued_at),
    do: {:error, :vendor_required}

  defp intended_email_digest(nil), do: nil
  defp intended_email_digest(""), do: nil

  defp intended_email_digest(email) when is_binary(email) do
    email |> String.trim() |> String.downcase() |> then(&:crypto.hash(:sha256, &1))
  end

  defp normalize_role(role) when is_atom(role), do: role

  defp normalize_role(role) when is_binary(role) do
    Enum.find(MembershipPolicy.roles(), role, &(Atom.to_string(&1) == role))
  end

  defp normalize_role(role), do: role
  defp value(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end
