defmodule Palee.Documents.Domain.SettingsPolicy do
  @moduledoc """
  A box's document rules (ADR-252):

    * `block_booking_on_unsigned` (default on): a client with an unsigned
      mandatory document cannot book;
    * `health_certificate_required` (default off): clients are asked for a
      health certificate, reminded before it expires, and a missing or
      expired one counts as an outstanding item;
    * `block_booking_on_health_certificate` (default off): without a valid
      certificate a client cannot book (turning it on also turns on
      `health_certificate_required`);
    * `health_certificate_validity_months` (1–24, default 12) and
      `health_certificate_reminder_days` (0–90, default 30).
  """

  @defaults %{
    block_booking_on_unsigned: true,
    health_certificate_required: false,
    block_booking_on_health_certificate: false,
    health_certificate_validity_months: 12,
    health_certificate_reminder_days: 30
  }

  @booleans ~w(block_booking_on_unsigned health_certificate_required
               block_booking_on_health_certificate)a
  @ranges %{health_certificate_validity_months: 1..24, health_certificate_reminder_days: 0..90}

  def defaults, do: @defaults
  def fields, do: Map.keys(@defaults)

  @doc "Saved settings over the defaults."
  def effective(nil), do: @defaults
  def effective(saved), do: Map.merge(@defaults, Map.take(saved, fields()))

  @doc "`{:ok, settings}` (the whole, effective set) or `{:error, {:invalid_fields, errors}}`."
  def validate(current, changes) do
    changes = Map.take(changes, fields())

    errors =
      Enum.reduce(changes, %{}, fn {field, value}, errors ->
        if valid?(field, value), do: errors, else: Map.put(errors, field, "invalid")
      end)

    if errors == %{} do
      merged = Map.merge(effective(current), changes)

      merged =
        if merged.block_booking_on_health_certificate,
          do: %{merged | health_certificate_required: true},
          else: merged

      {:ok, merged}
    else
      {:error, {:invalid_fields, errors}}
    end
  end

  @doc "Fields whose value differs between two setting maps."
  def changed(before, after_change),
    do: Enum.filter(fields(), &(Map.get(before, &1) != Map.get(after_change, &1)))

  defp valid?(field, value) when field in @booleans, do: is_boolean(value)
  defp valid?(field, value), do: is_integer(value) and value in Map.fetch!(@ranges, field)
end
