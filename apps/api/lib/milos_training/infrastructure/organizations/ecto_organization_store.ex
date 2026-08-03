defmodule MilosTraining.Infrastructure.Organizations.EctoOrganizationStore do
  @behaviour MilosTraining.Organizations.Ports.OrganizationStore

  import Ecto.Query

  alias Ecto.Multi
  alias MilosTraining.Organizations.Domain.InvitationPolicy

  alias MilosTraining.Organizations.{
    Organization,
    OrganizationDomain,
    OrganizationMembership,
    OrganizationSetting,
    RegistrationInvitation
  }

  alias MilosTraining.Repo

  @impl true
  def create_organization(params) do
    Multi.new()
    |> Multi.insert(:organization, Organization.changeset(params))
    |> Multi.insert(:settings, fn %{organization: organization} ->
      OrganizationSetting.changeset(%{
        organization_id: organization.id,
        timezone: value(params, :timezone) || "UTC",
        default_locale: value(params, :default_locale) || "en",
        invitation_lifetime_seconds: value(params, :invitation_lifetime_seconds) || 604_800,
        settings: value(params, :settings) || %{}
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{organization: organization}} -> {:ok, organization}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  @impl true
  def add_membership(params) do
    %OrganizationMembership{}
    |> OrganizationMembership.changeset(params)
    |> Repo.insert(
      on_conflict: {:replace, [:role, :status, :joined_at, :invited_by_user_id, :updated_at]},
      conflict_target: [:organization_id, :user_id],
      returning: true
    )
  end

  @impl true
  def issue_invitation(params, issued_at) do
    %RegistrationInvitation{}
    |> RegistrationInvitation.issue_changeset(params, issued_at)
    |> Repo.insert()
  end

  @impl true
  def revoke_invitation(organization_id, invitation_id, revoked_at) do
    Repo.transaction(fn ->
      invitation =
        RegistrationInvitation
        |> where(
          [invitation],
          invitation.id == ^invitation_id and invitation.organization_id == ^organization_id
        )
        |> lock("FOR UPDATE")
        |> Repo.one()

      if is_nil(invitation) or InvitationPolicy.state(invitation, revoked_at) != :active do
        Repo.rollback(:invalid_invitation)
      end

      invitation
      |> RegistrationInvitation.revoke_changeset(revoked_at)
      |> Repo.update()
      |> unwrap_or_rollback()
    end)
    |> flatten_transaction()
  end

  @impl true
  def redeem_invitation(digest, user_id, redeemed_at) do
    Repo.transaction(fn ->
      invitation =
        RegistrationInvitation
        |> where([invitation], invitation.token_digest == ^digest)
        |> lock("FOR UPDATE")
        |> Repo.one()

      if is_nil(invitation) or not InvitationPolicy.redeemable?(invitation, redeemed_at) do
        Repo.rollback(:invalid_invitation)
      end

      membership = upsert_redeemed_membership(invitation, user_id, redeemed_at)

      redeemed =
        invitation
        |> RegistrationInvitation.redeem_changeset(user_id, redeemed_at)
        |> Repo.update()
        |> unwrap_or_rollback()

      %{
        invitation: redeemed,
        membership: membership,
        organization: Repo.get!(Organization, invitation.organization_id)
      }
    end)
    |> flatten_transaction()
  end

  @impl true
  def get_organization_by_id(id), do: Repo.get(Organization, id)

  @impl true
  def get_organization_by_slug(slug), do: Repo.get_by(Organization, slug: slug)

  @impl true
  def get_organization_by_domain(host) do
    Organization
    |> join(:inner, [organization], domain in OrganizationDomain,
      on: domain.organization_id == organization.id
    )
    |> where([_organization, domain], domain.host == ^normalize_host(host))
    |> select([organization, _domain], organization)
    |> Repo.one()
  end

  @impl true
  def get_membership(organization_id, user_id) do
    Repo.get_by(OrganizationMembership,
      organization_id: organization_id,
      user_id: user_id
    )
  end

  @impl true
  def list_memberships(user_id) do
    OrganizationMembership
    |> join(:inner, [membership], organization in Organization,
      on: organization.id == membership.organization_id
    )
    |> where(
      [membership, organization],
      membership.user_id == ^user_id and membership.status == :active and
        organization.status == :active
    )
    |> order_by([_membership, organization], asc: organization.name)
    |> select([membership, organization], %{membership: membership, organization: organization})
    |> Repo.all()
  end

  @impl true
  def get_invitation_by_digest(digest),
    do: Repo.get_by(RegistrationInvitation, token_digest: digest)

  @impl true
  def get_invitation_with_organization(digest) do
    RegistrationInvitation
    |> join(:inner, [invitation], organization in Organization,
      on: organization.id == invitation.organization_id
    )
    |> where([invitation, _organization], invitation.token_digest == ^digest)
    |> select([invitation, organization], %{invitation: invitation, organization: organization})
    |> Repo.one()
  end

  defp upsert_redeemed_membership(invitation, user_id, redeemed_at) do
    params = %{
      organization_id: invitation.organization_id,
      user_id: user_id,
      role: invitation.role,
      status: :active,
      joined_at: redeemed_at,
      invited_by_user_id: invitation.issued_by_user_id
    }

    case get_membership(invitation.organization_id, user_id) do
      nil ->
        %OrganizationMembership{}
        |> OrganizationMembership.changeset(params)
        |> Repo.insert()
        |> unwrap_or_rollback()

      membership ->
        membership
        |> OrganizationMembership.changeset(params)
        |> Repo.update()
        |> unwrap_or_rollback()
    end
  end

  defp unwrap_or_rollback({:ok, value}), do: value
  defp unwrap_or_rollback({:error, reason}), do: Repo.rollback(reason)

  defp flatten_transaction({:ok, value}), do: {:ok, value}
  defp flatten_transaction({:error, reason}), do: {:error, reason}

  defp normalize_host(host) when is_binary(host),
    do: host |> String.trim() |> String.downcase() |> String.trim_trailing(".")

  defp normalize_host(_host), do: ""

  defp value(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end
