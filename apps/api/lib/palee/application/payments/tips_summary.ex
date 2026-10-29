defmodule Palee.Application.Payments.TipsSummary do
  @moduledoc """
  ADR-272: Finance › tips per staff member for a period, for the payroll
  hand-over (ν. 5162/2024: tips paid by card are the staff's, apart from
  revenue). One row per person a tip was attributed to, and one for the
  front desk role when a tip could not be given to one person; tips not
  attributed yet (paid before ADR-272) are a row of their own.
  """

  alias Palee.{Identity, Organizations, Payments}

  @page 200
  @max_days 366

  @doc "`params`: `from` and `to` (ISO dates, inclusive; default: this month)."
  def call(context, params) do
    with {:ok, from, to} <- period(context, params) do
      intents = tipped(context, from, to)
      names = names(intents)

      rows =
        intents
        |> Enum.group_by(&recipient/1)
        |> Enum.map(fn {{kind, user_id}, tips} ->
          %{
            kind: kind,
            user_id: user_id,
            name: user_id && Map.get(names, user_id),
            tip_cents: tips |> Enum.map(& &1.tip_cents) |> Enum.sum(),
            payments: length(tips)
          }
        end)
        |> Enum.sort_by(&{-&1.tip_cents, &1.name || ""})

      {:ok,
       %{
         from: from,
         to: to,
         currency: currency(intents),
         total_cents: rows |> Enum.map(& &1.tip_cents) |> Enum.sum(),
         rows: rows
       }}
    end
  end

  defp recipient(%{tip_recipient_user_id: id}) when is_binary(id), do: {"person", id}
  defp recipient(%{tip_attribution: "front_desk_role"}), do: {"front_desk_role", nil}
  defp recipient(_intent), do: {"unattributed", nil}

  defp tipped(context, from, to) do
    {starts, ends} = bounds(context, from, to)
    page(context, %{tipped: true, status: "succeeded", succeeded_from: starts, succeeded_to: ends}, 0, [])
  end

  defp page(context, filters, offset, acc) do
    %{intents: intents, total: total} =
      Payments.list_raw(context, Map.merge(filters, %{limit: @page, offset: offset}))

    acc = acc ++ intents
    if offset + @page < total and intents != [], do: page(context, filters, offset + @page, acc), else: acc
  end

  defp names(intents) do
    intents
    |> Enum.map(& &1.tip_recipient_user_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Identity.list_by_ids()
    |> Map.new(&{&1.id, &1.nickname})
  end

  defp currency([%{currency: currency} | _]), do: currency
  defp currency([]), do: nil

  defp period(context, params) do
    today = Organizations.local_today(context.organization_id, DateTime.utc_now())

    with {:ok, from} <- date(params[:from], Date.beginning_of_month(today)),
         {:ok, to} <- date(params[:to], today),
         true <- Date.compare(from, to) != :gt || {:error, :invalid_period},
         true <- Date.diff(to, from) < @max_days || {:error, :invalid_period} do
      {:ok, from, to}
    end
  end

  defp date(nil, default), do: {:ok, default}
  defp date(%Date{} = date, _default), do: {:ok, date}

  defp date(text, _default) when is_binary(text) do
    case Date.from_iso8601(text) do
      {:ok, date} -> {:ok, date}
      _invalid -> {:error, :invalid_period}
    end
  end

  # The business's local days, as UTC instants.
  defp bounds(context, from, to) do
    zone = Organizations.organization_timezone(context.organization_id)

    {local_start(from, zone), local_start(Date.add(to, 1), zone)}
  end

  defp local_start(date, zone) do
    case DateTime.new(date, ~T[00:00:00], zone) do
      {:ok, at} -> DateTime.shift_zone!(at, "Etc/UTC")
      {:gap, _before, at} -> DateTime.shift_zone!(at, "Etc/UTC")
      {:ambiguous, at, _later} -> DateTime.shift_zone!(at, "Etc/UTC")
      _error -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    end
  end
end
