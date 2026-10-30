defmodule Palee.PersonalData.RecordSource do
  @moduledoc """
  Facade over the configured personal data record source (ADR-267). It opens
  the session each `Catalog` entry is read in, so row-level security decides
  what is visible exactly as for the person's own requests:

    * `:account` entries in the person's own session (`app.user_id`);
    * `:tenant` entries once per business, in that business's session with
      the person as the acting profile (`app.organization_id`, `app.user_id`).
  """

  @behaviour Palee.PersonalData.Ports.RecordSource

  alias Palee.Infrastructure.Tenancy.RepoContext

  @impl true
  def organization_ids(user_id),
    do: RepoContext.run(%{user_id: user_id}, fn -> adapter().organization_ids(user_id) end)

  @impl true
  def rows(%{scope: :account} = entry, user_id, nil),
    do: RepoContext.run(%{user_id: user_id}, fn -> adapter().rows(entry, user_id, nil) end)

  def rows(%{scope: :tenant} = entry, user_id, organization_id) when is_binary(organization_id) do
    RepoContext.run(%{organization_id: organization_id, user_id: user_id}, fn ->
      adapter().rows(entry, user_id, organization_id)
    end)
  end

  defp adapter do
    Application.get_env(
      :palee,
      :personal_data_record_source,
      Palee.Infrastructure.PersonalData.EctoRecordSource
    )
  end
end
