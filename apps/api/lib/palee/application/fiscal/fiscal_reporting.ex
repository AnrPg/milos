defmodule Palee.Application.Fiscal.FiscalReporting do
  @moduledoc """
  Staff and system use cases of reporting to the tax authority (ADR-243):
  the myDATA connection, the transmissions screen, retrying a document,
  and sending what is due (right after an issue and every few minutes).
  """

  alias Palee.Fiscal.Reporting
  alias Palee.Workers.TransmitFiscalDocumentsJob

  @doc "`%{connection, environments}`; the subscription key is never returned."
  def connection(context),
    do: %{connection: Reporting.connection(context), environments: Reporting.environments()}

  def save_connection(context, params, now \\ DateTime.utc_now()) do
    params = %{
      environment: param(params, :environment),
      user_id: param(params, :user_id),
      subscription_key: param(params, :subscription_key)
    }

    with {:ok, connection} <-
           Reporting.save_connection(context, params, Map.get(context, :user_id), now) do
      schedule(context)
      {:ok, connection}
    end
  end

  @statuses ~w(pending sending accepted rejected failed)

  @doc "Transmissions with counts per status; filter `status`, paging `limit`/`offset`."
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
    |> Reporting.list(filters)
    |> Map.update!(:transmissions, fn rows -> Enum.map(rows, &view/1) end)
  end

  @doc "Sends a rejected or failed document again."
  def retry(context, document_id, now \\ DateTime.utc_now()) do
    with {:ok, transmission} <- Reporting.retry(context, document_id, now) do
      schedule(context, transmission.id)
      {:ok, view(transmission)}
    end
  end

  @doc "The transmission of each document id (for document lists and pages)."
  def for_documents(context, ids),
    do:
      context |> Reporting.transmissions_for(ids) |> Map.new(fn {id, row} -> {id, view(row)} end)

  @public ~w(id document_id authority status attempts next_attempt_at environment mark uid
             authentication_code qr_url accepted_at last_error_code last_error_message
             inserted_at updated_at)a

  defp view(transmission), do: Map.take(transmission, @public)

  @doc """
  Sends due transmissions of the tenant soon: a job when background jobs
  run, inline otherwise (tests, one-off tasks).
  """
  def schedule(%{organization_id: organization_id} = context, transmission_id \\ nil) do
    if Application.get_env(:palee, :start_oban, true) do
      %{"organization_id" => organization_id, "transmission_id" => transmission_id}
      |> TransmitFiscalDocumentsJob.new()
      |> Oban.insert()

      :ok
    else
      {:ok, _counts} = transmit(context, transmission_id || :due)
      :ok
    end
  end

  @doc "Sends what is due now for one tenant."
  def transmit(context, which \\ :due, now \\ DateTime.utc_now()),
    do: Reporting.transmit(context, which, now)

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
