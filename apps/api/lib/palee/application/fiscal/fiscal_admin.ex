defmodule Palee.Application.Fiscal.FiscalAdmin do
  @moduledoc """
  Staff use cases of the Fiscal context (ADR-240–242): the business's legal
  identity, the documents list, credit notes, journal verification, period
  closings and the audit archive. The gym's own clock (ADR-176) dates every
  document and closing.
  """

  alias Palee.{Fiscal, Organizations}
  alias Palee.Application.Fiscal.FiscalReporting

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
    transmissions = FiscalReporting.for_documents(context, Enum.map(page.documents, & &1.id))

    %{
      page
      | documents:
          Enum.map(page.documents, &Map.put(&1, :transmission, Map.get(transmissions, &1.id)))
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
         )}
    end
  end

  @doc """
  A credit note for document `id`: `lines: [%{position, quantity}]` or none
  for everything not yet credited. Idempotent by `idempotency_key`.
  """
  def credit(context, id, params, now \\ DateTime.utc_now()) do
    params = atomize(params, ~w(lines idempotency_key)a)

    requested =
      case params[:lines] do
        lines when is_list(lines) and lines != [] ->
          Enum.map(lines, &atomize(&1, ~w(position quantity)a))

        _ ->
          :all
      end

    with key when is_binary(key) and key != "" <-
           params[:idempotency_key] || {:error, :idempotency_key_required} do
      context
      |> Fiscal.credit(
        id,
        requested,
        Organizations.local_date(context, now),
        key,
        Map.get(context, :user_id),
        now
      )
      |> tap(fn
        {:ok, _note, :issued} -> FiscalReporting.schedule(context)
        _other -> :ok
      end)
    end
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
