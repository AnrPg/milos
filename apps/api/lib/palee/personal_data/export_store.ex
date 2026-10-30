defmodule Palee.PersonalData.ExportStore do
  @moduledoc """
  Facade over the configured personal data export store (ADR-267). The table
  is owner-only under row-level security, so every call runs in the person's
  own `RepoContext` session.
  """

  @behaviour Palee.PersonalData.Ports.ExportStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  @impl true
  def list(user_id), do: own(user_id, fn -> adapter().list(user_id) end)

  @impl true
  def get(id, user_id), do: own(user_id, fn -> adapter().get(id, user_id) end)

  @impl true
  def insert(%{user_id: user_id} = attrs), do: own(user_id, fn -> adapter().insert(attrs) end)

  @impl true
  def finish(%{user_id: user_id} = export, attrs),
    do: own(user_id, fn -> adapter().finish(export, attrs) end)

  defp own(user_id, fun) when is_binary(user_id), do: RepoContext.run(%{user_id: user_id}, fun)

  defp adapter do
    Application.get_env(
      :palee,
      :personal_data_export_store,
      Palee.Infrastructure.PersonalData.EctoExportStore
    )
  end
end
