defmodule MilosTraining.Infrastructure.Organizations.EctoOrganizationStore do
  @behaviour MilosTraining.Organizations.Ports.OrganizationStore

  import Ecto.Query

  alias Ecto.Multi
  alias MilosTraining.Organizations.Domain.InvitationPolicy

  alias MilosTraining.Organizations.{
    Organization,
    OrganizationDomain,
    OrganizationMembership,
    OrganizationProvisioningEvent,
    OrganizationSetting,
    RegistrationInvitation,
    Vendor
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
  def get_membership_by_id(organization_id, membership_id) do
    Repo.get_by(OrganizationMembership,
      id: membership_id,
      organization_id: organization_id
    )
  end

  @impl true
  def list_memberships(user_id) do
    OrganizationMembership
    |> join(:inner, [membership], organization in Organization,
      on: organization.id == membership.organization_id
    )
    |> join(:left, [_membership, organization], settings in OrganizationSetting,
      on: settings.organization_id == organization.id
    )
    |> where(
      [membership, organization, _settings],
      membership.user_id == ^user_id and membership.status == :active and
        organization.status == :active
    )
    |> order_by([_membership, organization, _settings], asc: organization.name)
    |> select([membership, organization, settings], %{
      membership: membership,
      organization: organization,
      settings: settings
    })
    |> Repo.all()
  end

  @impl true
  def list_organization_memberships(organization_id) do
    OrganizationMembership
    |> where([membership], membership.organization_id == ^organization_id)
    |> order_by([membership], asc: membership.inserted_at)
    |> Repo.all()
  end

  @impl true
  def list_active_membership_user_ids(organization_id) do
    OrganizationMembership
    |> where(
      [membership],
      membership.organization_id == ^organization_id and membership.status == :active
    )
    |> select([membership], membership.user_id)
    |> Repo.all()
  end

  @impl true
  def list_staff_user_ids(nil), do: []

  def list_staff_user_ids(organization_id) do
    OrganizationMembership
    |> where(
      [membership],
      membership.organization_id == ^organization_id and membership.status == :active and
        membership.role in [:owner, :admin, :coach]
    )
    |> select([membership], membership.user_id)
    |> Repo.all()
  end

  @impl true
  def list_membership_organization_ids(user_ids) do
    OrganizationMembership
    |> where([membership], membership.user_id in ^user_ids and membership.status == :active)
    |> select([membership], {membership.user_id, membership.organization_id})
    |> Repo.all()
    |> Enum.group_by(fn {user_id, _organization_id} -> user_id end, fn {_user_id, organization_id} ->
      organization_id
    end)
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

  @impl true
  def grant_vendor(user_id) do
    %Vendor{}
    |> Vendor.changeset(%{user_id: user_id, status: :active})
    |> Repo.insert(
      on_conflict: {:replace, [:status, :updated_at]},
      conflict_target: [:user_id],
      returning: true
    )
  end

  @impl true
  def revoke_vendor(user_id) do
    case Repo.get_by(Vendor, user_id: user_id) do
      nil ->
        {:error, :not_found}

      %Vendor{} = vendor ->
        vendor
        |> Vendor.changeset(%{status: :revoked})
        |> Repo.update()
    end
  end

  @impl true
  def get_vendor(user_id),
    do: Repo.get_by(Vendor, user_id: user_id, status: :active)

  @impl true
  def provision_organization(organization_params, invitation_params, platform_user_id, issued_at) do
    Multi.new()
    |> Multi.insert(:organization, Organization.changeset(organization_params))
    |> Multi.insert(:settings, fn %{organization: organization} ->
      OrganizationSetting.changeset(%{
        organization_id: organization.id,
        timezone: value(organization_params, :timezone) || "UTC",
        default_locale: value(organization_params, :default_locale) || "en",
        invitation_lifetime_seconds:
          value(organization_params, :invitation_lifetime_seconds) || 604_800,
        brand_name: value(organization_params, :brand_name),
        brand_logo_url: value(organization_params, :brand_logo_url),
        brand_primary_color: value(organization_params, :brand_primary_color),
        settings: value(organization_params, :settings) || %{}
      })
    end)
    |> Multi.insert(:invitation, fn %{organization: organization} ->
      invitation_params
      |> Map.put(:organization_id, organization.id)
      |> Map.put(:issued_by_user_id, platform_user_id)
      |> then(&RegistrationInvitation.issue_changeset(%RegistrationInvitation{}, &1, issued_at))
    end)
    |> Multi.insert(:owner_membership, fn %{organization: organization} ->
      OrganizationMembership.changeset(%{
        organization_id: organization.id,
        user_id: platform_user_id,
        role: :owner,
        status: :active,
        joined_at: issued_at,
        invited_by_user_id: platform_user_id
      })
    end)
    |> Multi.insert(:event, fn %{organization: organization} ->
      OrganizationProvisioningEvent.changeset(%{
        organization_id: organization.id,
        vendor_user_id: platform_user_id,
        event: "organization_provisioned",
        metadata: %{initial_owner_invitation: true, provisioning_owner_membership: true}
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  @impl true
  def list_organizations do
    Organization
    |> join(:left, [organization], settings in OrganizationSetting,
      on: settings.organization_id == organization.id
    )
    |> order_by([organization, _settings], asc: organization.name)
    |> select([organization, settings], %{organization: organization, settings: settings})
    |> Repo.all()
  end

  @impl true
  def delete_organization(organization_id, platform_user_id, deleted_at) do
    Repo.transaction(fn ->
      organization =
        Organization
        |> where([organization], organization.id == ^organization_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      if is_nil(organization), do: Repo.rollback(:not_found)

      %OrganizationProvisioningEvent{}
      |> OrganizationProvisioningEvent.changeset(%{
        organization_id: organization_id,
        vendor_user_id: platform_user_id,
        event: "organization_permanently_deleted",
        metadata: %{deleted_at: DateTime.to_iso8601(deleted_at)}
      })
      |> Repo.insert()
      |> unwrap_or_rollback()

      from(event in OrganizationProvisioningEvent,
        where: event.organization_id == ^organization_id
      )
      |> Repo.delete_all()

      organization
      |> Repo.delete()
      |> unwrap_or_rollback()
    end)
    |> flatten_transaction()
  end

  @impl true
  def update_organization_lifecycle(organization_id, status, platform_user_id, changed_at) do
    Repo.transaction(fn ->
      organization =
        Organization
        |> where([organization], organization.id == ^organization_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      if is_nil(organization), do: Repo.rollback(:not_found)

      updated =
        organization
        |> Organization.changeset(%{status: status})
        |> Repo.update()
        |> unwrap_or_rollback()

      %OrganizationProvisioningEvent{}
      |> OrganizationProvisioningEvent.changeset(%{
        organization_id: organization_id,
        vendor_user_id: platform_user_id,
        event: "organization_#{status}",
        metadata: %{changed_at: DateTime.to_iso8601(changed_at)}
      })
      |> Repo.insert()
      |> unwrap_or_rollback()

      updated
    end)
    |> flatten_transaction()
  end

  @impl true
  def rename_organization(organization_id, name, platform_user_id, changed_at) do
    Repo.transaction(fn ->
      organization =
        Organization
        |> where([organization], organization.id == ^organization_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      if is_nil(organization), do: Repo.rollback(:not_found)

      previous_name = organization.name

      updated =
        organization
        |> Organization.changeset(%{name: name})
        # Organization.changeset derives :slug from :name whenever :slug is
        # absent from the params - and since the slug's *value* isn't
        # actually changing, casting it explicitly doesn't register as a
        # change either (Ecto no-ops same-value casts), so derive_slug still
        # fires. Force the slug back after the fact instead: this is a
        # display-name-only rename, canonical_path/:org routing and any
        # bookmarked links must not move as a side effect of it.
        |> Ecto.Changeset.put_change(:slug, organization.slug)
        |> Repo.update()
        |> unwrap_or_rollback()

      %OrganizationProvisioningEvent{}
      |> OrganizationProvisioningEvent.changeset(%{
        organization_id: organization_id,
        vendor_user_id: platform_user_id,
        event: "organization_renamed",
        metadata: %{
          previous_name: previous_name,
          name: updated.name,
          changed_at: DateTime.to_iso8601(changed_at)
        }
      })
      |> Repo.insert()
      |> unwrap_or_rollback()

      updated
    end)
    |> flatten_transaction()
  end

  @impl true
  def get_organization_settings(organization_id),
    do: Repo.get_by(OrganizationSetting, organization_id: organization_id)

  @impl true
  def update_organization_settings(organization_id, params, platform_user_id, changed_at) do
    Repo.transaction(fn ->
      settings = Repo.get_by(OrganizationSetting, organization_id: organization_id)
      if is_nil(settings), do: Repo.rollback(:not_found)

      updated =
        settings
        |> OrganizationSetting.changeset(params)
        |> Repo.update()
        |> unwrap_or_rollback()

      %OrganizationProvisioningEvent{}
      |> OrganizationProvisioningEvent.changeset(%{
        organization_id: organization_id,
        vendor_user_id: platform_user_id,
        event: "organization_settings_updated",
        metadata: %{changed_at: DateTime.to_iso8601(changed_at)}
      })
      |> Repo.insert()
      |> unwrap_or_rollback()

      updated
    end)
    |> flatten_transaction()
  end

  @impl true
  def transaction(fun) when is_function(fun, 0) do
    if Repo.in_transaction?() do
      fun.()
    else
      Repo.transaction(fn ->
        case fun.() do
          {:ok, value} -> value
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> flatten_transaction()
    end
  end

  @impl true
  def update_membership_role(organization_id, membership_id, role) do
    Repo.transaction(fn ->
      membership = get_membership_by_id(organization_id, membership_id)
      if is_nil(membership), do: Repo.rollback(:not_found)

      membership
      |> OrganizationMembership.changeset(%{role: role})
      |> Repo.update()
      |> unwrap_or_rollback()
    end)
    |> flatten_transaction()
  end

  @impl true
  def update_membership_status(organization_id, membership_id, status) do
    Repo.transaction(fn ->
      membership = get_membership_by_id(organization_id, membership_id)
      if is_nil(membership), do: Repo.rollback(:not_found)

      membership
      |> OrganizationMembership.changeset(%{status: status})
      |> Repo.update()
      |> unwrap_or_rollback()
    end)
    |> flatten_transaction()
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
