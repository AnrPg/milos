defmodule Palee.Application.Fiscal.FiscalEInvoicing do
  @moduledoc """
  Staff and system use cases of Peppol e-invoicing (ADR-250): the network
  connection, the submissions screen, retrying a document, the access
  point's webhook, and sending and polling what is due (right after an
  issue and every few minutes).
  """

  alias Palee.Application.PublicURL
  alias Palee.Fiscal.EInvoicing
  alias Palee.Workers.SendEInvoicesJob

  @doc "`%{connection, environments}`; the API key and webhook token are never returned."
  def connection(context),
    do: %{connection: EInvoicing.connection(context), environments: EInvoicing.environments()}

  @doc """
  Saves the connection. The answer carries `webhook_url` only when a new
  webhook token was made (first save or rotation): it is shown once.
  """
  def save_connection(context, params, now \\ DateTime.utc_now()) do
    params = %{
      environment: param(params, :environment),
      peppol_id: param(params, :peppol_id),
      legal_entity_id: param(params, :legal_entity_id),
      provider: param(params, :provider),
      api_key: param(params, :api_key),
      api_secret: param(params, :api_secret),
      rotate_webhook_token: param(params, :rotate_webhook_token) == true
    }

    with {:ok, connection} <-
           EInvoicing.save_connection(context, params, Map.get(context, :user_id), now) do
      schedule(context)
      {token, connection} = Map.pop(connection, :webhook_token)

      {:ok,
       Map.put(
         connection,
         :webhook_url,
         token && webhook_url(context.organization_id, token)
       )}
    end
  end

  defp webhook_url(organization_id, token) do
    (PublicURL.base_url() |> String.trim_trailing("/")) <>
      "/api/webhooks/peppol/#{organization_id}/#{token}"
  end

  @statuses ~w(pending sending submitted delivered rejected failed uncertain)

  @doc "Submissions with counts per status; filter `status`, paging `limit`/`offset`."
  def list(context, params) do
    status = param(params, :status)

    filters =
      %{
        status: if(status in @statuses, do: status),
        limit: integer(param(params, :limit)),
        offset: integer(param(params, :offset))
      }
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    context
    |> EInvoicing.list(filters)
    |> Map.update!(:submissions, fn rows -> Enum.map(rows, &view/1) end)
  end

  @doc "A submission with its attempt log, or `{:error, :not_found}`."
  def get(context, id) do
    case EInvoicing.get(context, id) do
      nil ->
        {:error, :not_found}

      submission ->
        {:ok,
         submission
         |> view()
         |> Map.put(:attempts_log, Enum.map(submission.attempts_log, &attempt_view/1))}
    end
  end

  @doc "Sends a refused, failed or uncertain document again."
  def retry(context, document_id, now \\ DateTime.utc_now()) do
    with {:ok, submission} <- EInvoicing.retry(context, document_id, now) do
      schedule(context, submission.id)
      {:ok, view(submission)}
    end
  end

  @doc "The submission of each document id (for document lists and pages)."
  def for_documents(context, ids),
    do: context |> EInvoicing.submissions_for(ids) |> Map.new(fn {id, row} -> {id, view(row)} end)

  @doc "An access point webhook: wakes the polls it names. `:ok` or `{:error, :not_found}`."
  def webhook(context, token, body, now \\ DateTime.utc_now()) do
    with :ok <- EInvoicing.webhook(context, token, body, now) do
      schedule(context)
      :ok
    end
  end

  @public ~w(id document_id network status attempts polls next_attempt_at environment
             recipient_scheme recipient_identifier provider_submission_id submitted_at
             delivered_at last_error_code last_error_message inserted_at updated_at)a

  defp view(submission), do: Map.take(submission, @public)

  @attempt ~w(id attempt operation environment outcome response_status error duration_ms
              started_at)a

  defp attempt_view(attempt), do: Map.take(attempt, @attempt)

  @doc """
  Sends due submissions of the tenant soon: a job when background jobs run,
  inline otherwise (tests, one-off tasks).
  """
  def schedule(%{organization_id: organization_id} = context, submission_id \\ nil) do
    if Application.get_env(:palee, :start_oban, true) do
      %{"organization_id" => organization_id, "submission_id" => submission_id}
      |> SendEInvoicesJob.new()
      |> Oban.insert()

      :ok
    else
      {:ok, _counts} = transmit(context, submission_id || :due)
      :ok
    end
  end

  @doc "Sends and polls what is due now for one tenant."
  def transmit(context, which \\ :due, now \\ DateTime.utc_now()),
    do: EInvoicing.transmit(context, which, now)

  defp param(params, key) when is_map(params),
    do: Map.get(params, key, Map.get(params, Atom.to_string(key)))

  defp param(_params, _key), do: nil

  defp integer(value) when is_integer(value) and value >= 0, do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number >= 0 -> number
      _ -> nil
    end
  end

  defp integer(_value), do: nil
end
