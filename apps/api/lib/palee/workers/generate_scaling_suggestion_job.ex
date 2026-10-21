defmodule Palee.Workers.GenerateScalingSuggestionJob do
  @moduledoc """
  One advisor call for one athlete's assignment (ADR-174). Transient
  provider errors retry with backoff; a rejected key, a refusal or a switched
  off gym end the job without retrying.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 3_600, fields: [:worker, :args], keys: [:assignment_id, :athlete_id]]

  alias Palee.Application.ScalingSuggestions
  alias Palee.Organizations

  @final_errors [
    :scaling_disabled,
    :not_needed,
    :advisor_key_rejected,
    :advisor_not_configured,
    :advisor_refused
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "organization_id" => organization_id,
          "assignment_id" => assignment_id,
          "athlete_id" => athlete_id
        }
      }) do
    with {:ok, context} <-
           Organizations.resolve_system_tenant_context(organization_id, :scaling_suggestions),
         {:ok, _outcome} <- ScalingSuggestions.generate(context, assignment_id, athlete_id) do
      :ok
    else
      {:error, reason} when reason in @final_errors -> {:cancel, reason}
      {:error, :organization_not_found} -> {:cancel, :organization_not_found}
      {:error, reason} -> {:error, reason}
    end
  end
end
