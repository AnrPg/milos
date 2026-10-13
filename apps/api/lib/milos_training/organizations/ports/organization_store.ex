defmodule MilosTraining.Organizations.Ports.OrganizationStore do
  alias MilosTraining.Organizations.{
    Organization,
    OrganizationMembership,
    OrganizationPurge,
    OrganizationSetting,
    OrganizationSlugAlias,
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
  # ADR-122 retired slug aliases.
  @callback get_organization_by_slug_alias(String.t()) :: Organization.t() | nil
  @callback get_canonical_slug_for_alias(String.t()) :: String.t() | nil
  @callback list_slug_aliases(Ecto.UUID.t()) :: [OrganizationSlugAlias.t()]
  @callback count_pending_invitations(Ecto.UUID.t(), DateTime.t()) :: non_neg_integer()
  @callback rename_organization_slug(
              Ecto.UUID.t(),
              String.t(),
              String.t() | nil,
              Ecto.UUID.t(),
              DateTime.t()
            ) ::
              {:ok,
               %{
                 organization: Organization.t(),
                 previous_slug: String.t(),
                 aliases: [OrganizationSlugAlias.t()]
               }}
              | {:error, term()}
  @callback get_membership(Ecto.UUID.t(), Ecto.UUID.t()) :: OrganizationMembership.t() | nil
  @callback get_membership_by_id(Ecto.UUID.t(), Ecto.UUID.t()) :: OrganizationMembership.t() | nil
  @callback list_memberships(Ecto.UUID.t()) :: [map()]
  @callback list_organization_memberships(Ecto.UUID.t()) :: [OrganizationMembership.t()]
  @callback list_active_membership_user_ids(Ecto.UUID.t()) :: [Ecto.UUID.t()]
  @callback list_staff_user_ids(Ecto.UUID.t()) :: [Ecto.UUID.t()]
  @callback list_member_roles(Ecto.UUID.t(), [String.t()] | nil, Ecto.UUID.t() | nil) :: [map()]
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
  # ADR-121: sets (`%{object_key, url}`) or clears (nil) the uploaded logo and
  # records the audit event in one transaction.
  @callback replace_organization_logo(
              Ecto.UUID.t(),
              %{object_key: String.t(), url: String.t()} | nil,
              %{user_id: Ecto.UUID.t(), scope: :tenant | :vendor},
              DateTime.t()
            ) ::
              {:ok,
               %{
                 settings: OrganizationSetting.t(),
                 previous_object_key: String.t() | nil,
                 event: String.t() | nil
               }}
              | {:error, term()}
  @callback update_membership_status(Ecto.UUID.t(), Ecto.UUID.t(), atom()) ::
              {:ok, OrganizationMembership.t()} | {:error, term()}
  @callback update_membership_role(Ecto.UUID.t(), Ecto.UUID.t(), atom()) ::
              {:ok, OrganizationMembership.t()} | {:error, term()}
  @callback set_organization_status(Ecto.UUID.t(), atom()) :: {:ok, struct()} | {:error, term()}
  @callback put_organization_setting(Ecto.UUID.t(), String.t(), term()) ::
              {:ok, struct()} | {:error, term()}
  @callback update_membership_roles(Ecto.UUID.t(), Ecto.UUID.t(), [atom()]) ::
              {:ok, struct()} | {:error, term()}
  @callback update_membership_settings(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
              {:ok, struct()} | {:error, term()}
  @callback put_organization_settings_entry(Ecto.UUID.t(), String.t(), term()) ::
              {:ok, OrganizationSetting.t()} | {:error, term()}
  @callback list_active_invitations(Ecto.UUID.t(), DateTime.t()) :: [RegistrationInvitation.t()]
  @callback transaction((-> {:ok, term()} | {:error, term()})) :: {:ok, term()} | {:error, term()}

  # ADR-117 reviewed tenant purge records (platform-level, survive the purge).
  @callback request_organization_purge(Ecto.UUID.t(), Ecto.UUID.t(), atom(), DateTime.t()) ::
              {:ok, %{purge: OrganizationPurge.t(), organization: Organization.t()}}
              | {:error, term()}
  @callback get_purge(Ecto.UUID.t()) :: OrganizationPurge.t() | nil
  @callback lock_purge(Ecto.UUID.t()) :: OrganizationPurge.t() | nil
  @callback get_open_purge(Ecto.UUID.t()) :: OrganizationPurge.t() | nil
  @callback get_latest_purge(Ecto.UUID.t()) :: OrganizationPurge.t() | nil
  @callback list_purges(pos_integer()) :: [OrganizationPurge.t()]
  @callback update_purge(OrganizationPurge.t(), map()) ::
              {:ok, OrganizationPurge.t()} | {:error, term()}
  @callback finalize_purge(OrganizationPurge.t(), map(), Ecto.UUID.t(), DateTime.t()) ::
              {:ok, OrganizationPurge.t()} | {:error, term()}
end
