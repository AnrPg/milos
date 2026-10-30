defmodule Palee.Organizations.Commands.RecordPlatformEvent do
  @moduledoc """
  ADR-273: the Palee team's change to a box made outside the
  organization's own tables (its fiscal connections), written to the
  vendors' audit log `organization_provisioning_events`. Metadata never
  holds a credential; callers pass only what changed.
  """

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.{OrganizationStore, PlatformContext}

  def call(%PlatformContext{user_id: user_id}, organization_id, %{event: event} = attrs)
      when is_binary(event) do
    RepoContext.run(%{user_id: user_id}, fn ->
      OrganizationStore.insert_provisioning_event(%{
        organization_id: organization_id,
        vendor_user_id: user_id,
        event: event,
        metadata: Map.get(attrs, :metadata, %{})
      })
    end)
  end

  def call(_context, _organization_id, _attrs), do: {:error, :vendor_required}

  @doc "True when the organization exists (read as the vendor)."
  def exists?(%PlatformContext{user_id: user_id}, organization_id) do
    case Ecto.UUID.cast(organization_id) do
      {:ok, id} ->
        RepoContext.run(%{user_id: user_id}, fn ->
          not is_nil(OrganizationStore.get_organization_by_id(id))
        end)

      :error ->
        false
    end
  end

  def exists?(_context, _organization_id), do: false
end
