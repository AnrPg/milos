defmodule MilosTraining.Organizations.Ports.OrganizationStore do
  alias MilosTraining.Organizations.{
    Organization,
    OrganizationMembership,
    OrganizationSetting,
    RegistrationInvitation,
    Vendor
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
  @callback get_membership_by_id(Ecto.UUID.t(), Ecto.UUID.t()) :: OrganizationMembership.t() | nil
  @callback list_memberships(Ecto.UUID.t()) :: [map()]
  @callback list_organization_memberships(Ecto.UUID.t()) :: [OrganizationMembership.t()]
  @callback list_active_membership_user_ids(Ecto.UUID.t()) :: [Ecto.UUID.t()]
  @callback list_staff_user_ids(Ecto.UUID.t()) :: [Ecto.UUID.t()]
  @callback list_membership_organization_ids([Ecto.UUID.t()]) :: %{
              Ecto.UUID.t() => [Ecto.UUID.t()]
            }
  @callback list_deletable_organization_user_ids(Ecto.UUID.t(), Ecto.UUID.t()) :: [
              Ecto.UUID.t()
            ]
  @callback get_invitation_by_digest(binary()) :: RegistrationInvitation.t() | nil
  @callback get_invitation_with_organization(binary()) :: map() | nil
  @callback grant_vendor(Ecto.UUID.t()) ::
              {:ok, Vendor.t()} | {:error, Ecto.Changeset.t()}
  @callback revoke_vendor(Ecto.UUID.t()) :: {:ok, Vendor.t()} | {:error, term()}
  @callback get_vendor(Ecto.UUID.t()) :: Vendor.t() | nil
  @callback provision_organization(map(), map(), Ecto.UUID.t(), DateTime.t()) ::
              {:ok, map()} | {:error, term()}
  @callback list_organizations() :: [map()]
  @callback delete_organization(Ecto.UUID.t(), Ecto.UUID.t(), DateTime.t()) ::
              {:ok, Organization.t()} | {:error, term()}
  @callback update_organization_lifecycle(Ecto.UUID.t(), atom(), Ecto.UUID.t(), DateTime.t()) ::
              {:ok, Organization.t()} | {:error, term()}
  @callback rename_organization(Ecto.UUID.t(), String.t(), Ecto.UUID.t(), DateTime.t()) ::
              {:ok, Organization.t()} | {:error, term()}
  @callback record_invitation_email_sent(Ecto.UUID.t(), Ecto.UUID.t(), binary() | nil) ::
              {:ok, term()} | {:error, term()}
  @callback get_organization_settings(Ecto.UUID.t()) :: OrganizationSetting.t() | nil
  @callback update_organization_settings(Ecto.UUID.t(), map(), Ecto.UUID.t(), DateTime.t()) ::
              {:ok, OrganizationSetting.t()} | {:error, term()}
  @callback update_membership_status(Ecto.UUID.t(), Ecto.UUID.t(), atom()) ::
              {:ok, OrganizationMembership.t()} | {:error, term()}
  @callback update_membership_role(Ecto.UUID.t(), Ecto.UUID.t(), atom()) ::
              {:ok, OrganizationMembership.t()} | {:error, term()}
  @callback transaction((-> {:ok, term()} | {:error, term()})) :: {:ok, term()} | {:error, term()}
end
