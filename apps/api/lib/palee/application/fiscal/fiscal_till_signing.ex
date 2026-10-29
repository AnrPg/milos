defmodule Palee.Application.Fiscal.FiscalTillSigning do
  @moduledoc """
  Staff and system use cases of cash-register security (ADR-251): the TSE
  or RKSV connection, the signatures screen with what each receipt
  prints, retrying a signature, an RKSV null receipt, and signing what is
  due (right after an issue and every few minutes).
  """

  alias Palee.Application.Fiscal.FiscalConnections
  alias Palee.Fiscal.TillSigning
  alias Palee.Workers.SignTillReceiptsJob

  @doc "`%{connection, environments}`; the credentials are never returned."
  def connection(context, device),
    do: %{
      connection: TillSigning.connection(context, device),
      environments: TillSigning.environments()
    }

  @doc """
  Saves (and, when needed, provisions) the till device, then checks it
  (ADR-273): `{:ok, %{connection, check}}`.
  """
  def save_connection(context, device, params, now \\ DateTime.utc_now(), opts \\ []) do
    params = %{
      environment: param(params, :environment),
      api_key: param(params, :api_key),
      api_secret: param(params, :api_secret),
      reprovision: param(params, :reprovision) == true,
      updated_by_platform: Keyword.get(opts, :platform) == true
    }

    with :ok <- FiscalConnections.guard(context, opts),
         {:ok, _connection} <-
           TillSigning.save_connection(context, device, params, Map.get(context, :user_id), now) do
      result = FiscalConnections.after_save(context, device, now)
      schedule(context)
      {:ok, result}
    end
  end

  @statuses ~w(pending sending signed uncertain device_failed rejected failed)

  @doc "Signatures with counts per status; filters `status`, `device`, paging `limit`/`offset`."
  def list(context, params) do
    status = param(params, :status)
    device = param(params, :device)

    filters =
      %{
        status: if(status in @statuses, do: status),
        device: if(device in TillSigning.devices(), do: device),
        limit: integer(param(params, :limit)),
        offset: integer(param(params, :offset))
      }
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    context
    |> TillSigning.list(filters)
    |> Map.update!(:signatures, fn rows -> Enum.map(rows, &view/1) end)
  end

  @doc "A signature with what it prints and its attempt log, or `{:error, :not_found}`."
  def get(context, id) do
    case TillSigning.get(context, id) do
      nil ->
        {:error, :not_found}

      signature ->
        {:ok,
         signature
         |> view()
         |> Map.put(:attempts_log, Enum.map(signature.attempts_log, &attempt_view/1))}
    end
  end

  def retry(context, id, now \\ DateTime.utc_now()) do
    with {:ok, signature} <- TillSigning.retry(context, id, now) do
      schedule(context, signature.id)
      {:ok, view(signature)}
    end
  end

  @doc "Queues an RKSV null receipt and signs it soon."
  def null_receipt(context, now \\ DateTime.utc_now()) do
    with {:ok, signature} <- TillSigning.null_receipt(context, now) do
      schedule(context, signature.id)
      {:ok, view(signature)}
    end
  end

  @doc "The signature of each document id (for document lists and pages)."
  def for_documents(context, ids),
    do: context |> TillSigning.signatures_for(ids) |> Map.new(fn {id, row} -> {id, view(row)} end)

  @public ~w(id document_id device kind period status attempts next_attempt_at environment
             transaction_number signature_counter signature_value signature_algorithm time_format
             started_at_device finished_at_device unit_serial register_serial receipt_number
             qr_code_data signed_at failed_at last_error_code last_error_message inserted_at
             updated_at)a

  defp view(signature),
    do: signature |> Map.take(@public) |> Map.put(:print, TillSigning.print(signature))

  @attempt ~w(id attempt operation environment outcome response_status error duration_ms
              started_at)a

  defp attempt_view(attempt), do: Map.take(attempt, @attempt)

  def schedule(%{organization_id: organization_id} = context, signature_id \\ nil) do
    if Application.get_env(:palee, :start_oban, true) do
      %{"organization_id" => organization_id, "signature_id" => signature_id}
      |> SignTillReceiptsJob.new()
      |> Oban.insert()

      :ok
    else
      {:ok, _counts} = transmit(context, signature_id || :due)
      :ok
    end
  end

  @doc "Signs what is due now for one tenant."
  def transmit(context, which \\ :due, now \\ DateTime.utc_now()),
    do: TillSigning.transmit(context, which, now)

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
