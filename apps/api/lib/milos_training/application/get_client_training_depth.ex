defmodule MilosTraining.Application.GetClientTrainingDepth do
  @moduledoc """
  `GET /api/org/:slug/staff/clients/:user_id/progress-depth` (ADR-165): a
  coach sees a client's muscle coverage summary, qualities radar and
  training load, built only from what the client lets that gym's coaches
  read.

  - Only a coach of the gym who may see the client's training
    (`view_client_training`: their own clients, every client for a head
    coach, ADR-100), and only while the client is an active member there.
  - Only executions and log entries on a rung that reaches the coach and
    shared with this gym (ADR-139 §6, ADR-162 «Οι coach μου»), read in the
    coach's tenant session, so the journal's coach seam and row security
    decide; private entries never count and nothing tells the coach they
    exist. Felt feedback follows its entry (ADR-163).
  - Aggregates only: no entry, note or workout text is returned, so the
    per-entry coach-read audit is not written.
  """

  alias MilosTraining.Application.{AuthorizeClientAccess, TrainingDepth}
  alias MilosTraining.Organizations

  @default_range "4w"

  def call(context, client_id, params, today \\ Date.utc_today())

  def call(%{organization_id: organization_id} = context, client_id, params, today)
      when is_binary(organization_id) do
    with {:ok, range} <- range(Map.get(params, "range")),
         {:ok, client_id} <- authorize(context, client_id) do
      {:ok,
       TrainingDepth.build(context, range, today,
         user_id: client_id,
         scope: {:coach, organization_id}
       )}
    end
  end

  def call(_context, _client_id, _params, _today), do: {:error, :organization_context_required}

  defp range(nil), do: {:ok, @default_range}
  defp range(""), do: {:ok, @default_range}

  defp range(range) do
    if range in TrainingDepth.ranges(),
      do: {:ok, range},
      else: {:error, [range: "has an unknown value"]}
  end

  defp authorize(context, client_id) do
    with {:ok, client_id} <- cast(client_id),
         true <- Organizations.acting_user_coaches?(context) || {:error, :forbidden},
         true <-
           client_id in Organizations.list_active_membership_user_ids(context) ||
             {:error, :not_found},
         :ok <- AuthorizeClientAccess.call(context, :view_client_training, client_id) do
      {:ok, client_id}
    end
  end

  defp cast(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end
end
