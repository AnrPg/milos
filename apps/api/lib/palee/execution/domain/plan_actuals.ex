defmodule Palee.Execution.Domain.PlanActuals do
  @moduledoc """
  ADR-270: the athlete's actuals for a structured plan, one record per set /
  round of each plan row, prescribed next to actual, as the web runner sends
  them with the completion (`plan_actuals`).

  Pure: checks every record against the workout's plan sections (the section
  is one of them, the row is in it, the block is the row's own, -1 only for
  interruption rows) and turns numbers into two-decimal `Decimal`s. A record
  the client could not have produced is `{:error, :bad_request}`, so a stale
  or tampered client cannot store garbage. A record for the same place twice
  keeps the last one.
  """

  @max_records 2_000
  @max_text 200
  @max_number Decimal.new("99999999.99")

  @typedoc """
  The plan rows of each section: section id => row id => the row's block
  (`-1` for an interruption row). Built from the plan by the caller.
  """
  @type rows_by_section :: %{String.t() => %{String.t() => integer()}}

  @type record :: %{
          section_id: String.t(),
          row_id: String.t(),
          exercise_name: String.t(),
          exercise_ref: String.t() | nil,
          block_index: integer(),
          round_index: pos_integer(),
          part_index: non_neg_integer(),
          phase_index: non_neg_integer(),
          interrupt: boolean(),
          prescribed_reps_text: String.t(),
          prescribed_load_text: String.t(),
          prescribed_reps: Decimal.t() | nil,
          prescribed_load_kg: Decimal.t() | nil,
          prescribed_load_pct: Decimal.t() | nil,
          one_rep_max_kg: Decimal.t() | nil,
          actual_reps: Decimal.t() | nil,
          actual_load_kg: Decimal.t() | nil,
          logged: boolean()
        }

  @numbers ~w(prescribed_reps prescribed_load_kg prescribed_load_pct one_rep_max_kg actual_reps actual_load_kg)a
  @texts ~w(prescribed_reps_text prescribed_load_text)a

  def max_records, do: @max_records

  @doc "`{:ok, records}` (nil or absent: none) or `{:error, :bad_request}`."
  @spec normalize(term(), rows_by_section()) :: {:ok, [record()]} | {:error, :bad_request}
  def normalize(nil, _rows_by_section), do: {:ok, []}

  def normalize(entries, rows_by_section)
      when is_list(entries) and length(entries) <= @max_records and is_map(rows_by_section) do
    entries
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      case record(entry, rows_by_section) do
        {:ok, record} -> {:cont, {:ok, [record | acc]}}
        :error -> {:halt, {:error, :bad_request}}
      end
    end)
    |> case do
      {:ok, records} -> {:ok, records |> Enum.reverse() |> dedupe()}
      error -> error
    end
  end

  def normalize(_entries, _rows_by_section), do: {:error, :bad_request}

  @doc "Where a record sits in the run: one record per place."
  @spec place(record()) :: tuple()
  def place(record),
    do:
      {record.section_id, record.row_id, record.interrupt, record.block_index, record.round_index,
       record.part_index, record.phase_index}

  @doc """
  The volume of one record in kg × reps: actual reps times actual load, when
  both are numbers (a bodyweight or qualitative load has none).
  """
  @spec tonnage(map()) :: Decimal.t()
  def tonnage(%{actual_reps: %Decimal{} = reps, actual_load_kg: %Decimal{} = kg}),
    do: Decimal.mult(reps, kg)

  def tonnage(_record), do: Decimal.new(0)

  @doc "A record with its decimals as JSON numbers (integers when whole)."
  @spec to_json(map()) :: map()
  def to_json(record) do
    Enum.reduce(@numbers, record, fn key, acc ->
      case Map.get(acc, key) do
        %Decimal{} = value -> Map.put(acc, key, number(value))
        _other -> acc
      end
    end)
  end

  defp number(decimal) do
    if Decimal.integer?(decimal),
      do: decimal |> Decimal.normalize() |> Decimal.to_integer(),
      else: decimal |> Decimal.normalize() |> Decimal.to_float()
  end

  defp dedupe(records) do
    {kept, _seen} =
      records
      |> Enum.reverse()
      |> Enum.reduce({[], MapSet.new()}, fn record, {acc, seen} ->
        key = place(record)

        if MapSet.member?(seen, key),
          do: {acc, seen},
          else: {[record | acc], MapSet.put(seen, key)}
      end)

    kept
  end

  defp record(%{} = entry, rows_by_section) do
    with {:ok, section_id} <- text(field(entry, :section_id), true),
         %{} = rows <- Map.get(rows_by_section, section_id, :error),
         {:ok, row_id} <- text(field(entry, :row_id), true),
         row_block when is_integer(row_block) <- Map.get(rows, row_id, :error),
         {:ok, interrupt} <- boolean(field(entry, :interrupt), false),
         {:ok, block_index} <- integer(field(entry, :block_index), -1),
         true <- block_index == row_block and interrupt == (row_block == -1),
         {:ok, round_index} <- integer(field(entry, :round_index), 1),
         {:ok, part_index} <- integer(field(entry, :part_index, 0), 0),
         {:ok, phase_index} <- integer(field(entry, :phase_index, 0), 0),
         {:ok, name} <- text(field(entry, :exercise_name, ""), false),
         {:ok, ref} <- optional_text(field(entry, :exercise_ref)),
         {:ok, logged} <- boolean(field(entry, :logged), false),
         {:ok, texts} <- texts(entry),
         {:ok, numbers} <- numbers(entry) do
      {:ok,
       %{
         section_id: section_id,
         row_id: row_id,
         exercise_name: name,
         exercise_ref: ref,
         block_index: block_index,
         round_index: round_index,
         part_index: part_index,
         phase_index: phase_index,
         interrupt: interrupt,
         logged: logged
       }
       |> Map.merge(texts)
       |> Map.merge(numbers)}
    else
      _invalid -> :error
    end
  end

  defp record(_entry, _rows_by_section), do: :error

  defp field(entry, key, default \\ nil) do
    case Map.fetch(entry, key) do
      {:ok, value} -> value
      :error -> Map.get(entry, Atom.to_string(key), default)
    end
  end

  defp texts(entry) do
    Enum.reduce_while(@texts, {:ok, %{}}, fn key, {:ok, acc} ->
      case text(field(entry, key, ""), false) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp numbers(entry) do
    Enum.reduce_while(@numbers, {:ok, %{}}, fn key, {:ok, acc} ->
      case decimal(field(entry, key)) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp text(value, required?) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      String.length(trimmed) > @max_text -> :error
      required? and trimmed == "" -> :error
      true -> {:ok, trimmed}
    end
  end

  defp text(nil, false), do: {:ok, ""}
  defp text(_value, _required?), do: :error

  defp optional_text(nil), do: {:ok, nil}

  defp optional_text(value) do
    case text(value, false) do
      {:ok, ""} -> {:ok, nil}
      other -> other
    end
  end

  defp boolean(value, _default) when is_boolean(value), do: {:ok, value}
  defp boolean(nil, default), do: {:ok, default}
  defp boolean(_value, _default), do: :error

  defp integer(value, min) when is_integer(value) and value >= min and value <= 100_000,
    do: {:ok, value}

  defp integer(_value, _min), do: :error

  defp decimal(nil), do: {:ok, nil}
  defp decimal(value) when is_integer(value), do: bounded(Decimal.new(value))

  defp decimal(value) when is_float(value),
    do: bounded(value |> Decimal.from_float() |> Decimal.round(2))

  defp decimal(_value), do: :error

  defp bounded(decimal) do
    if Decimal.negative?(decimal) or Decimal.gt?(decimal, @max_number),
      do: :error,
      else: {:ok, Decimal.round(decimal, 2)}
  end
end
