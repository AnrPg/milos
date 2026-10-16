defmodule MilosTraining.Application.GetClientJournal do
  @moduledoc """
  `GET /api/org/:slug/staff/clients/:user_id/journal` (ADR-139 §6): a coach
  reads one member's journal in the gym, through the ADR-129 coach seam. Only
  entries recorded in this gym on a rung that reaches the coach are listed,
  plus every injury and review there; nothing tells the coach that hidden
  entries exist. Every entry returned is written to the coach-read audit.
  """

  alias MilosTraining.Application.JournalFeed
  alias MilosTraining.{Journal, Organizations}

  def call(%{organization_id: organization_id, user_id: reader_id} = context, client_id, params)
      when is_binary(organization_id) do
    with :ok <- coach(context),
         {:ok, client_id} <- member(context, client_id) do
      Journal.with_context(context, fn ->
        with {:ok, page} <- JournalFeed.page(client_id, {:coach, organization_id}, params) do
          page.items
          |> Enum.map(
            &%{
              organization_id: organization_id,
              reader_user_id: reader_id,
              owner_user_id: client_id,
              entry_kind: &1.kind,
              entry_id: &1.id
            }
          )
          |> Journal.record_coach_reads()

          {:ok, page}
        end
      end)
    end
  end

  def call(_context, _client_id, _params), do: {:error, :organization_context_required}

  defp coach(context),
    do: if(Organizations.acting_user_coaches?(context), do: :ok, else: {:error, :forbidden})

  defp member(context, client_id) do
    with {:ok, client_id} <- Ecto.UUID.cast(client_id),
         true <- client_id in Organizations.list_active_membership_user_ids(context) do
      {:ok, client_id}
    else
      _other -> {:error, :not_found}
    end
  end
end
