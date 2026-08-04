defmodule MilosTraining.Organizations.Ports.OrganizationStore do
  alias MilosTraining.Organizations.{
    Organization,
    OrganizationMembership,
    OrganizationSetting,
    PlatformOwner,
    RegistrationInvitation
  }

  @callback create_organization(map()) ::
              {:ok, Organization.t()} | {:error, Ecto.Changeset.t() | term()}
  @callback add_membership(map()) ::
              {:ok, OrganizationMembership.t()} | {:error, Ecto.Changeset.t()}
  @callback issue_invitation(map(), DateTime.t()) ::
              {:ok, RegistrationInvitation.t()} | {:error, Ecto.Changeset.t()}
  @callback revoke_invitation(Ecto.UUID.t(), Ecto.UUID.t(), DateTime.t()) ::
              {:ok, RegistrationInvitation.t()} | {:error, term()}
  @callback redeem_invitation(binary(), Ecto.UUID.t(), DateTime.t()) ::
              {:ok, map()} | {:error, :invalid_invitation | Ecto.Changeset.t()}
  @callback get_organization_by_id(Ecto.UUID.t()) :: Organization.t() | nil
  @callback get_organization_by_slug(String.t()) :: Organization.t() | nil
  @callback get_organization_by_domain(String.t()) :: Organization.t() | nil
  @callback get_membership(Ecto.UUID.t(), Ecto.UUID.t()) :: OrganizationMembership.t() | nil
  @callback list_memberships(Ecto.UUID.t()) :: [map()]
  @callback list_active_membership_user_ids(Ecto.UUID.t()) :: [Ecto.UUID.t()]
  @callback get_invitation_by_digest(binary()) :: RegistrationInvitation.t() | nil
  @callback get_invitation_with_organization(binary()) :: map() | nil
  @callback grant_platform_owner(Ecto.UUID.t()) ::
              {:ok, PlatformOwner.t()} | {:error, Ecto.Changeset.t()}
  @callback get_platform_owner(Ecto.UUID.t()) :: PlatformOwner.t() | nil
  @callback provision_organization(map(), map(), Ecto.UUID.t(), DateTime.t()) ::
              {:ok, map()} | {:error, term()}
  @callback list_organizations() :: [map()]
  @callback delete_organization(Ecto.UUID.t(), Ecto.UUID.t(), DateTime.t()) ::
              {:ok, Organization.t()} | {:error, term()}
  @callback update_organization_lifecycle(Ecto.UUID.t(), atom(), Ecto.UUID.t(), DateTime.t()) ::
              {:ok, Organization.t()} | {:error, term()}
  @callback get_organization_settings(Ecto.UUID.t()) :: OrganizationSetting.t() | nil
  @callback update_organization_settings(Ecto.UUID.t(), map(), Ecto.UUID.t(), DateTime.t()) ::
              {:ok, OrganizationSetting.t()} | {:error, term()}
end
