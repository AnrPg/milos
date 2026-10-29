defmodule Palee.Imports.Domain.DateParser do
  @moduledoc """
  ADR-254: dates as other systems and spreadsheets write them. Pure.

  The order of day, month and year is chosen per import (`dmy`, `mdy`,
  `ymd`), because `03/04/2025` is 3 April in Greece and 4 March in the US.
  A four-digit first part is always year-month-day (ISO 8601). Also read:

    * separators `/`, `.`, `-` and space; a time after the date is ignored
      (`2025-03-04 18:30`, `2025-03-04T18:30:00Z`);
    * two-digit years: 00–69 → 2000s, 70–99 → 1900s;
    * month names in English and Greek (`4 Mar 2025`, `March 4, 2025`,
      `4 Μαρ 2025`);
    * Excel serial dates (`45720` = 2025-03-04): whole numbers from 1 to
      100000 counted from 1899-12-30, as Excel's 1900 date system does.

  `guess_order/1` proposes an order from a column's values: a first part
  above 12 rules out `mdy`, a second part above 12 rules out `dmy`.
  """

  @orders ~w(dmy mdy ymd)
  @excel_epoch ~D[1899-12-30]
  @max_serial 100_000

  @months %{
    "jan" => 1,
    "feb" => 2,
    "mar" => 3,
    "apr" => 4,
    "may" => 5,
    "jun" => 6,
    "jul" => 7,
    "aug" => 8,
    "sep" => 9,
    "oct" => 10,
    "nov" => 11,
    "dec" => 12,
    "ιαν" => 1,
    "φεβ" => 2,
    "μαρ" => 3,
    "απρ" => 4,
    "μαι" => 5,
    "μαϊ" => 5,
    "ιουν" => 6,
    "ιουλ" => 7,
    "αυγ" => 8,
    "σεπ" => 9,
    "οκτ" => 10,
    "νοε" => 11,
    "δεκ" => 12
  }

  def orders, do: @orders

  @doc "`{:ok, date}`, `:blank` or `{:error, :invalid_date}`."
  def parse(value, order \\ "dmy")

  def parse(nil, _order), do: :blank

  def parse(value, order) when is_binary(value) and order in @orders do
    value = String.trim(value)

    cond do
      value == "" -> :blank
      Regex.match?(~r/^\d{1,6}(\.0+)?$/, value) -> serial(value)
      true -> value |> strip_time() |> textual(order)
    end
  end

  def parse(_value, _order), do: {:error, :invalid_date}

  defp serial(value) do
    {days, _rest} = Integer.parse(value)

    if days >= 1 and days <= @max_serial,
      do: {:ok, Date.add(@excel_epoch, days)},
      else: {:error, :invalid_date}
  end

  defp strip_time(value) do
    value
    |> String.replace(~r/[T\s]\d{1,2}:\d{2}(:\d{2}(\.\d+)?)?\s*([ap]\.?m\.?)?\s*(Z|[+-]\d{2}:?\d{2})?$/iu, "")
    |> String.trim()
  end

  defp textual(value, order) do
    parts =
      value
      |> String.downcase()
      |> String.replace(",", " ")
      |> String.split(~r/[\/\.\-\s]+/u, trim: true)

    case parts do
      [a, b, c] -> three(a, b, c, order)
      _other -> {:error, :invalid_date}
    end
  end

  defp three(a, b, c, order) do
    named = Enum.map([a, b, c], &month_name/1)

    cond do
      # "4 mar 2025" / "mar 4 2025"
      match?([_, m, _] when is_integer(m), named) -> build(c, Enum.at(named, 1), a)
      match?([m, _, _] when is_integer(m), named) -> build(c, Enum.at(named, 0), b)
      String.length(a) == 4 -> build(a, b, c)
      order == "dmy" -> build(c, b, a)
      order == "mdy" -> build(c, a, b)
      order == "ymd" -> build(a, b, c)
    end
  end

  defp month_name(part) do
    if Regex.match?(~r/^\d+$/, part) do
      nil
    else
      key = part |> String.normalize(:nfd) |> String.replace(~r/\p{Mn}/u, "")
      Enum.find_value(@months, fn {name, month} -> String.starts_with?(key, name) && month end)
    end
  end

  defp build(year, month, day) do
    with {:ok, year} <- year(year),
         {:ok, month} <- number(month),
         {:ok, day} <- number(day),
         {:ok, date} <- Date.new(year, month, day) do
      {:ok, date}
    else
      _error -> {:error, :invalid_date}
    end
  end

  defp year(value) when is_binary(value) do
    case Integer.parse(value) do
      {year, ""} when year >= 1000 and year <= 9999 -> {:ok, year}
      {year, ""} when byte_size(value) == 2 and year < 70 -> {:ok, 2000 + year}
      {year, ""} when byte_size(value) == 2 -> {:ok, 1900 + year}
      _other -> :error
    end
  end

  defp number(value) when is_integer(value), do: {:ok, value}

  defp number(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> {:ok, number}
      _other -> :error
    end
  end

  defp number(_value), do: :error

  @doc """
  The order that reads every value in `values` (a column), preferring
  `default`; nil when no order reads them all.
  """
  def guess_order(values, default \\ "dmy") when is_list(values) do
    candidates = [default | List.delete(@orders, default)]

    present = Enum.reject(values, &(is_nil(&1) or String.trim(&1) == ""))

    Enum.find(candidates, fn order ->
      Enum.all?(present, fn value -> match?({:ok, _date}, parse(value, order)) end)
    end)
  end
end
