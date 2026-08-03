defmodule MilosTraining.Organizations do
  alias MilosTraining.Organizations.Commands.{
    AddMembership,
    CreateOrganization,
    IssueInvitation,
    RedeemInvitation,
    RevokeInvitation
  }

  alias MilosTraining.Organizations.Queries.{
    FindOrganization,
    InspectInvitation,
    ListMemberships,
    ResolveTenantContext
  }

  @legacy_organization %{name: "Legacy Milos Training", slug: "legacy-milos-training"}

  def legacy_organization_slug, do: @legacy_organization.slug

  defdelegate create_organization(params), to: CreateOrganization, as: :call
  defdelegate add_membership(params), to: AddMembership, as: :call
  defdelegate get_by_id(id), to: FindOrganization, as: :by_id
  defdelegate get_by_slug(slug), to: FindOrganization, as: :by_slug
  defdelegate get_by_domain(host), to: FindOrganization, as: :by_domain
  defdelegate list_memberships(user_id), to: ListMemberships, as: :call

  def issue_invitation(context, params, issued_at \\ DateTime.utc_now()),
    do: IssueInvitation.call(context, params, issued_at)

  def revoke_invitation(context, invitation_id, revoked_at \\ DateTime.utc_now()),
    do: RevokeInvitation.call(context, invitation_id, revoked_at)

  def inspect_invitation(token, now \\ DateTime.utc_now()),
    do: InspectInvitation.call(token, now)

  def redeem_invitation(token, user_id, redeemed_at \\ DateTime.utc_now()),
    do: RedeemInvitation.call(token, user_id, redeemed_at)

  def resolve_tenant_context(account, slug, request_metadata \\ %{}),
    do: ResolveTenantContext.call(account, slug, request_metadata)

  def ensure_legacy_organization do
    case get_by_slug(@legacy_organization.slug) do
      nil -> create_legacy_organization()
      organization -> {:ok, organization}
    end
  end

  def ensure_legacy_membership(account, role \\ nil) do
    with {:ok, organization} <- ensure_legacy_organization() do
      add_membership(%{
        organization_id: organization.id,
        user_id: account.id,
        role: role || legacy_membership_role(account.role),
        status: :active,
        joined_at: DateTime.utc_now()
      })
    end
  end

  defp create_legacy_organization do
    case create_organization(@legacy_organization) do
      {:ok, organization} ->
        {:ok, organization}

      {:error, reason} ->
        case get_by_slug(@legacy_organization.slug) do
          nil -> {:error, reason}
          organization -> {:ok, organization}
        end
    end
  end

  defp legacy_membership_role(:admin), do: :owner
  defp legacy_membership_role(:athlete), do: :athlete
  defp legacy_membership_role(_role), do: :member
end
