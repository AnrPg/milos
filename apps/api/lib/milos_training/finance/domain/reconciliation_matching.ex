defmodule MilosTraining.Finance.Domain.ReconciliationMatching do
  @moduledoc """
  Pure rules for manual payment-provider reconciliation (ADR-126).

  A statement line is one external movement: a provider `payment` (money in)
  or `refund` (money out), identified by a provider key and the provider's
  own reference. A payment line matches a `membership_payments` fact; a
  refund line matches a `finance_payment_reversals` fact. Matching never
  changes the internal fact - it records the link plus any discrepancies:

  * `type_mismatch` - a payment line linked to a reversal or vice versa
  * `amount_mismatch` - statement amount differs from the internal amount
  * `currency_mismatch`
  * `date_out_of_tolerance` - more than 3 days between the dates
  * `provider_not_settled` - the provider reports `pending` or `failed`
  * `internal_not_settled` - the internal payment is not `paid`

  No discrepancies => `matched`; otherwise `mismatched` (flagged for review).
  """

  @date_tolerance_days 3
  @candidate_window_days 14
  @provider_pattern ~r/^[a-z0-9][a-z0-9_.-]{0,39}$/
  @external_types ["payment", "refund"]
  @external_statuses ["settled", "pending", "failed"]
  @max_reference_length 120
  @max_description_length 500

  def date_tolerance_days, do: @date_tolerance_days
  def external_types, do: @external_types
  def external_statuses, do: @external_statuses

  @doc """
  Validates and normalizes a statement line. Returns `{:ok, line}` with atom
  keys or `{:error, [{field, message}]}`.
  """
  def normalize_statement_line(params) when is_map(params) do
    fields = [
      provider: &provider/1,
      external_reference: &reference/1,
      external_type: &enum(&1, @external_types, nil),
      external_status: &enum(&1, @external_statuses, "settled"),
      statement_amount_cents: &positive_integer/1,
      statement_currency: &currency/1,
      statement_occurred_on: &date/1,
      statement_description: &description/1
    ]

    {line, errors} =
      Enum.reduce(fields, {%{}, []}, fn {field, normalizer}, {line, errors} ->
        case normalizer.(value(params, field)) do
          {:ok, normalized} -> {Map.put(line, field, normalized), errors}
          {:error, message} -> {line, [{field, message} | errors]}
        end
      end)

    case errors do
      [] -> {:ok, line}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  def normalize_statement_line(_params), do: {:error, [{:base, "is invalid"}]}

  @doc """
  True when an incoming line reuses an existing `(provider, reference)` with
  different economic content - a replay must be identical to be idempotent.
  """
  def replay_conflict?(existing, line) do
    Enum.any?(
      [:external_type, :statement_amount_cents, :statement_currency, :statement_occurred_on],
      fn field -> Map.get(existing, field) != Map.get(line, field) end
    )
  end

  @doc "Internal fact kind a statement line type reconciles against."
  def target_kind("payment"), do: :payment
  def target_kind("refund"), do: :reversal

  @doc "Parses an API target type."
  def parse_target_type("payment"), do: {:ok, :payment}
  def parse_target_type("reversal"), do: {:ok, :reversal}
  def parse_target_type(_value), do: {:error, :invalid_reconciliation_target}

  @doc """
  Compares a statement line with an internal fact
  (`%{kind, amount_cents, currency, occurred_on, status}`).
  """
  def evaluate(line, fact) do
    discrepancies =
      []
      |> add_if(target_kind(line.external_type) != fact.kind, "type_mismatch")
      |> add_if(line.statement_amount_cents != fact.amount_cents, "amount_mismatch")
      |> add_if(
        normalize_currency(line.statement_currency) != normalize_currency(fact.currency),
        "currency_mismatch"
      )
      |> add_if(
        days_apart(line.statement_occurred_on, fact.occurred_on) > @date_tolerance_days,
        "date_out_of_tolerance"
      )
      |> add_if(line.external_status != "settled", "provider_not_settled")
      |> add_if(not internal_settled?(fact), "internal_not_settled")
      |> Enum.reverse()

    %{
      status: if(discrepancies == [], do: "matched", else: "mismatched"),
      discrepancies: discrepancies
    }
  end

  @doc """
  Ranks internal facts as match candidates: same kind and currency, and
  either the same amount or a date within #{@candidate_window_days} days.
  Exact amount first, then nearest date. Facts already linked elsewhere are
  expected to be filtered by the caller.
  """
  def rank_candidates(line, facts, limit \\ 10) do
    kind = target_kind(line.external_type)
    currency = normalize_currency(line.statement_currency)

    facts
    |> Enum.filter(fn fact ->
      fact.kind == kind and normalize_currency(fact.currency) == currency and
        (fact.amount_cents == line.statement_amount_cents or
           days_apart(line.statement_occurred_on, fact.occurred_on) <= @candidate_window_days)
    end)
    |> Enum.map(fn fact -> Map.put(fact, :evaluation, evaluate(line, fact)) end)
    |> Enum.sort_by(fn fact ->
      {abs(fact.amount_cents - line.statement_amount_cents),
       days_apart(line.statement_occurred_on, fact.occurred_on), to_string(Map.get(fact, :id))}
    end)
    |> Enum.take(limit)
  end

  @doc "Inclusive date window used to load candidate facts."
  def candidate_window(%Date{} = occurred_on) do
    {Date.add(occurred_on, -@candidate_window_days),
     Date.add(occurred_on, @candidate_window_days)}
  end

  defp internal_settled?(%{kind: :payment, status: status}), do: status == "paid"
  defp internal_settled?(_fact), do: true

  defp add_if(list, true, code), do: [code | list]
  defp add_if(list, _condition, _code), do: list

  defp days_apart(%Date{} = left, %Date{} = right), do: abs(Date.diff(left, right))
  defp days_apart(_left, _right), do: @candidate_window_days + 1

  defp normalize_currency(nil), do: nil
  defp normalize_currency(value), do: value |> to_string() |> String.upcase()

  defp value(params, field), do: Map.get(params, field, Map.get(params, Atom.to_string(field)))

  defp provider(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()

    if Regex.match?(@provider_pattern, normalized),
      do: {:ok, normalized},
      else: {:error, "must be 1-40 lowercase letters, digits, dots, dashes or underscores"}
  end

  defp provider(_value), do: {:error, "can't be blank"}

  defp reference(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, "can't be blank"}
      trimmed when byte_size(trimmed) > @max_reference_length -> {:error, "is too long"}
      trimmed -> {:ok, trimmed}
    end
  end

  defp reference(_value), do: {:error, "can't be blank"}

  defp enum(value, allowed, default) when value in [nil, ""] do
    if default, do: {:ok, default}, else: {:error, "must be one of: #{Enum.join(allowed, ", ")}"}
  end

  defp enum(value, allowed, _default) when is_binary(value) do
    if value in allowed,
      do: {:ok, value},
      else: {:error, "must be one of: #{Enum.join(allowed, ", ")}"}
  end

  defp enum(_value, allowed, _default),
    do: {:error, "must be one of: #{Enum.join(allowed, ", ")}"}

  defp positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _ -> {:error, "must be a positive integer amount in cents"}
    end
  end

  defp positive_integer(_value), do: {:error, "must be a positive integer amount in cents"}

  defp currency(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.upcase()

    if Regex.match?(~r/^[A-Z]{3}$/, normalized),
      do: {:ok, normalized},
      else: {:error, "must be a three-letter ISO 4217 code"}
  end

  defp currency(nil), do: {:ok, "EUR"}
  defp currency(_value), do: {:error, "must be a three-letter ISO 4217 code"}

  defp date(%Date{} = value), do: {:ok, value}

  defp date(value) when is_binary(value) do
    case Date.from_iso8601(String.trim(value)) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, "must be an ISO 8601 date"}
    end
  end

  defp date(_value), do: {:error, "must be an ISO 8601 date"}

  defp description(value) when value in [nil, ""], do: {:ok, nil}

  defp description(value) when is_binary(value),
    do: {:ok, value |> String.trim() |> String.slice(0, @max_description_length)}

  defp description(_value), do: {:error, "must be text"}
end
