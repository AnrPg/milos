defmodule Palee.BusinessAccounts.Ports.BusinessAccountStore do
  @moduledoc """
  Persistence port of ADR-184's business accounts: activation links,
  requests to the platform team and the rows demo seeders wrote. Every
  callback runs in the session the facade opened.
  """

  alias Palee.BusinessAccounts.{ActivationLink, BusinessRequest, DemoRecord}

  @callback transaction((-> {:ok, term()} | {:error, term()})) :: {:ok, term()} | {:error, term()}

  @callback issue_activation_link(map(), DateTime.t()) ::
              {:ok, ActivationLink.t()} | {:error, Ecto.Changeset.t()}
  @callback revoke_activation_link(Ecto.UUID.t(), DateTime.t()) ::
              {:ok, ActivationLink.t()} | {:error, :not_found}
  @callback list_activation_links([Ecto.UUID.t()] | :all) :: [ActivationLink.t()]
  @callback get_activation_link_by_digest(binary()) :: ActivationLink.t() | nil
  @callback activate_business(binary(), DateTime.t()) ::
              {:ok, Ecto.UUID.t()}
              | {:error, :invalid_activation_link | :business_already_active}

  @callback create_request(map()) :: {:ok, BusinessRequest.t()} | {:error, Ecto.Changeset.t()}
  @callback get_request(Ecto.UUID.t()) :: BusinessRequest.t() | nil
  @callback list_requests(map()) :: [BusinessRequest.t()]
  @callback update_request(BusinessRequest.t(), Ecto.Changeset.t()) ::
              {:ok, BusinessRequest.t()} | {:error, Ecto.Changeset.t()}

  @callback track_demo_records(Ecto.UUID.t(), String.t(), [{String.t(), Ecto.UUID.t()}]) ::
              :ok
  @callback list_demo_records(Ecto.UUID.t()) :: [DemoRecord.t()]
  @callback delete_demo_rows(Ecto.UUID.t(), [DemoRecord.t()]) :: :ok
  @callback clear_demo_records(Ecto.UUID.t()) :: :ok
  @callback demo_person?(Ecto.UUID.t(), Ecto.UUID.t()) :: boolean()
  @callback notification_suppressed?(Ecto.UUID.t() | nil, Ecto.UUID.t()) :: boolean()
  @callback deletable_sources() :: [String.t()]

  # Abandoned demos (ADR-184 follow-up): the lifecycle columns of
  # `organizations`, written only through narrow SECURITY DEFINER functions.
  @callback touch_demo_activity(Ecto.UUID.t() | nil, DateTime.t(), pos_integer()) ::
              non_neg_integer()
  @callback idle_demo_organizations(DateTime.t()) :: [
              %{
                organization_id: Ecto.UUID.t(),
                last_active_at: DateTime.t(),
                reminder_sent_at: DateTime.t() | nil,
                owner_ids: [Ecto.UUID.t()]
              }
            ]
  @callback claim_demo_reminder(Ecto.UUID.t(), DateTime.t(), DateTime.t()) ::
              {:ok, DateTime.t()} | :not_claimed
  @callback mark_demo_archived(Ecto.UUID.t(), DateTime.t(), DateTime.t(), DateTime.t()) ::
              boolean()
  @callback close_demo_activation(Ecto.UUID.t(), DateTime.t()) :: :ok
  @callback list_archived_demos() :: [map()]
  @callback reopen_demo_business(Ecto.UUID.t(), DateTime.t()) ::
              {:ok, Ecto.UUID.t()} | {:error, :not_found}
end
