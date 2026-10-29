defmodule Palee.Finance.Domain.ValueOverride do
  @moduledoc """
  ADR-274: a value Palee works out that staff set by hand. Pure rules; the
  store keeps the rows (`finance_value_overrides`).

  Every override keeps who set it, when, the value Palee had worked out at
  that moment (`computed_value`) and the value staff chose; rows are never
  deleted, so they are the change history. At most one override per value
  is in force (`ended_at` nil). It ends when:

    * staff put the value back to automatic (`"reset"`), or set it again
      (`"replaced"`);
    * for the status, Palee's own value changes from the one it replaced
      (`"lapsed"`): a payment, a new period or a leave decides again, so an
      exception for this month never hides next month's debt. A date set by
      hand stays until it is reset.

  Fields:

    * `"status"` of a membership (`MemberStatus.overridable/0`);
    * `"ends_on"` of a subscription (an ISO date, the subscription's last day).
  """

  alias Palee.Finance.Domain.MemberStatus

  @fields %{"status" => "membership", "ends_on" => "subscription"}
  @end_reasons ~w(reset replaced lapsed)
  @max_reason 500

  def fields, do: Map.keys(@fields)
  def end_reasons, do: @end_reasons

  @doc "The kind of record a field belongs to."
  def subject_type(field), do: Map.get(@fields, field)

  @doc "Checks a value staff typed for a field; returns it in its stored form."
  def validate("status", value) do
    if value in MemberStatus.overridable(),
      do: {:ok, value},
      else: {:error, :invalid_override_value}
  end

  def validate("ends_on", value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, Date.to_iso8601(date)}
      {:error, _reason} -> {:error, :invalid_override_value}
    end
  end

  def validate(field, _value) when is_map_key(@fields, field),
    do: {:error, :invalid_override_value}

  def validate(_field, _value), do: {:error, :invalid_override_field}

  @doc "A reason is optional; it is trimmed and cut to a sane length."
  def reason(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> String.slice(text, 0, @max_reason)
    end
  end

  def reason(_value), do: nil

  @doc """
  Whether an override in force has lapsed now that Palee works out
  `computed`: only the status lapses, when its automatic value moved on.
  """
  def lapsed?(%{field: "status", computed_value: replaced}, computed),
    do: replaced != computed

  def lapsed?(_override, _computed), do: false

  @doc "The automatic value of a date field, as the history stores it."
  def stored_value(%Date{} = date), do: Date.to_iso8601(date)
  def stored_value(nil), do: nil
  def stored_value(value) when is_binary(value), do: value
end
