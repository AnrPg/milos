defmodule Palee.Application.Fiscal.FiscalAdmin do
  @moduledoc """
  Staff use cases of the Fiscal context (ADR-240–242): the business's legal
  identity, the documents list, credit notes, journal verification, period
  closings and the audit archive. The gym's own clock (ADR-176) dates every
  document and closing.
  """

  alias Palee.{Fiscal, Organizations}
  alias Palee.Application.Fiscal.{
    CreditRefunds,
    FiscalEInvoicing,
    FiscalReporting,
    FiscalTillSigning
  }

  @doc "Supported countries and their requirements."
  def countries, do: %{countries: Fiscal.countries(), vat_schemes: Fiscal.vat_schemes()}

  @doc "`%{identity, profile, missing, complete}`."
  def identity(context), do: Fiscal.identity_status(context)

  def save_identity(context, params, now \\ DateTime.utc_now()) do
    Fiscal.save_identity(
      context,
      atomize(params, identity_keys()),
      Map.get(context, :user_id),
      now
    )
  end

  @doc "Documents, newest first, with `total` for paging and each one's report state."
  def list_documents(context, params) do
    filters =
      params
      |> atomize(~w(kind from to number limit offset)a)
      |> Map.update(:from, nil, &date/1)
      |> Map.update(:to, nil, &date/1)
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    page = Fiscal.list_documents(context, filters)
    ids = Enum.map(page.documents, & &1.id)
    transmissions = FiscalReporting.for_documents(context, ids)
    submissions = FiscalEInvoicing.for_documents(context, ids)
    signatures = FiscalTillSigning.for_documents(context, ids)

    %{
      page
      | documents:
          Enum.map(page.documents, fn document ->
            document
            |> Map.put(:transmission, Map.get(transmissions, document.id))
            |> Map.put(:einvoice, Map.get(submissions, document.id))
            |> Map.put(:till_signature, Map.get(signatures, document.id))
          end)
    }
  end

  @doc "A document with its lines and the credit notes against it."
  def document(context, id) do
    case Fiscal.get_document(context, id) do
      nil ->
        {:error, :not_found}

      document ->
        {:ok,
         document
         |> Map.put(:credit_notes, Fiscal.credit_notes(context, document.id))
         |> Map.put(
           :transmission,
           context |> FiscalReporting.for_documents([document.id]) |> Map.get(document.id)
         )
         |> Map.put(
           :einvoice,
           context |> FiscalEInvoicing.for_documents([document.id]) |> Map.get(document.id)
         )
         |> Map.put(
           :till_signature,
           context |> FiscalTillSigning.for_documents([document.id]) |> Map.get(document.id)
         )
         |> Map.put(:refund_option, CreditRefunds.option(context, document))}
    end
  end

  @doc """
  A credit note for document `id`: `lines: [%{position, quantity}]` or none
  for everything not yet credited, with its `reason` (ADR-265). Idempotent
  by `idempotency_key`.

  With `refund: true` the money goes back to the card the document was paid
  with, and that refund issues the note (`CreditRefunds`, ADR-262).

  `{:ok, %{document: note | nil, refund: refund | nil}, :issued | :replayed}`.
  """
  def credit(context, id, params, now \\ DateTime.utc_now()) do
    params = atomize(params, ~w(lines idempotency_key reason refund)a)

    requested =
      case params[:lines] do
        lines when is_list(lines) and lines != [] ->
          Enum.map(lines, &atomize(&1, ~w(position quantity)a))

        _ ->
          :all
      end

    with key when is_binary(key) and key != "" <-
           params[:idempotency_key] || {:error, :idempotency_key_required},
         {:ok, reason} <- staff_reason(params[:reason]) do
      request = %{
        requested: requested,
        reason: reason,
        key: key,
        issue_date: Organizations.local_date(context, now)
      }

      context
      |> issue_credit(id, request, params[:refund] == true, now)
      |> tap(fn
        {:ok, %{document: %{}}, :issued} ->
          FiscalReporting.schedule(context)
          FiscalEInvoicing.schedule(context)
          FiscalTillSigning.schedule(context)

        _other ->
          :ok
      end)
    end
  end

  defp issue_credit(context, id, request, true = _refund, now),
    do: CreditRefunds.credit_and_refund(context, id, request, Map.get(context, :user_id), now)

  defp issue_credit(context, id, request, false = _refund, now) do
    case Fiscal.credit(
           context,
           id,
           request.requested,
           request.issue_date,
           request.key,
           Map.get(context, :user_id),
           now,
           reason: request.reason
         ) do
      {:ok, note, mode} -> {:ok, %{document: note, refund: nil}, mode}
      error -> error
    end
  end

  # Staff always say why (mockup s2): one of the four reasons.
  defp staff_reason(reason) do
    if reason in Fiscal.credit_reasons(),
      do: {:ok, reason},
      else: {:error, {:invalid_fields, %{reason: [if(reason, do: "invalid", else: "required")]}}}
  end

  def verify_journal(context, now \\ DateTime.utc_now()),
    do: Fiscal.verify_journal(context, Map.get(context, :user_id), now)

  def closings(context, params) do
    filters =
      params
      |> atomize(~w(kind from to limit)a)
      |> Map.update(:from, nil, &date/1)
      |> Map.update(:to, nil, &date/1)
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    Fiscal.list_closings(context, filters)
  end

  @max_archive_days 3_660

  @doc "The signed audit archive of `from`..`to` (inclusive, gym-local dates)."
  def archive(context, params, now \\ DateTime.utc_now()) do
    params = atomize(params, ~w(from to)a)

    with %Date{} = from <- date(params[:from]) || {:error, :invalid_date_range},
         %Date{} = to <- date(params[:to]) || {:error, :invalid_date_range},
         true <-
           (Date.compare(from, to) != :gt and Date.diff(to, from) <= @max_archive_days) ||
             {:error, :invalid_date_range} do
      Fiscal.archive(context, from, to, Map.get(context, :user_id), now)
    end
  end

  @doc "Closes every gym-local period that has ended (hourly job, idempotent)."
  def close_due_periods(context, now \\ DateTime.utc_now()),
    do: Fiscal.close_due_periods(context, Organizations.local_date(context, now), now)

  defp identity_keys,
    do: ~w(legal_name trade_name country_code tax_id vat_number tax_office registration_number
           activity_code vat_scheme street building_number postal_code city region email phone
           document_language branch_code fiscal_year_start_month iban qr_iban)a

  defp atomize(params, keys) when is_map(params) do
    Enum.reduce(keys, %{}, fn key, acc ->
      case Map.fetch(params, key) do
        {:ok, value} ->
          Map.put(acc, key, value)

        :error ->
          case Map.fetch(params, Atom.to_string(key)) do
            {:ok, value} -> Map.put(acc, key, value)
            :error -> acc
          end
      end
    end)
  end

  defp atomize(_params, _keys), do: %{}

  defp date(%Date{} = date), do: date

  defp date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp date(_value), do: nil
end
