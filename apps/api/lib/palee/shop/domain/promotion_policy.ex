defmodule Palee.Shop.Domain.PromotionPolicy do
  @moduledoc """
  Product-scoped promotion codes (ADR-190 «Προώθηση»), pure.

    * A code is 3–32 of `A-Z 0-9 - _`, case-insensitive (stored upper case).
    * It takes `discount_percent` (1–100) off the line, or `discount_cents`
      off each unit (never below zero).
    * It is redeemable while active, inside its window and under its cap;
      redemptions are the buyer-facing orders that used it and are not
      cancelled.
    * It applies only to the lines of its product; a cart without that
      product refuses it (`promotion_code_not_applicable`).
    * It never stacks with the member discount: each line takes the larger
      of the two.
  """

  @code_format ~r/^[A-Z0-9_-]{3,32}$/

  def code_format, do: @code_format

  @doc "The stored form of a typed code: trimmed, upper case, spaces as `-`."
  def normalize_code(nil), do: nil

  def normalize_code(code) when is_binary(code) do
    code
    |> String.trim()
    |> String.upcase()
    |> String.replace(~r/\s+/, "-")
  end

  def normalize_code(_code), do: nil

  @doc "Whether `code` (a promotion code) can be redeemed now."
  @spec redeemable(map(), DateTime.t()) :: :ok | {:error, atom()}
  def redeemable(code, now) do
    cond do
      not code.active ->
        {:error, :promotion_code_invalid}

      match?(%DateTime{}, code.starts_at) and DateTime.compare(now, code.starts_at) == :lt ->
        {:error, :promotion_code_invalid}

      match?(%DateTime{}, code.ends_at) and DateTime.compare(now, code.ends_at) != :lt ->
        {:error, :promotion_code_expired}

      is_integer(code.max_redemptions) and (code.redemptions || 0) >= code.max_redemptions ->
        {:error, :promotion_code_exhausted}

      true ->
        :ok
    end
  end

  @doc "The status a card or the staff list shows: active | scheduled | expired | exhausted | inactive."
  def status(code, now) do
    case redeemable(code, now) do
      :ok -> :active
      {:error, :promotion_code_expired} -> :expired
      {:error, :promotion_code_exhausted} -> :exhausted
      {:error, :promotion_code_invalid} -> if code.active, do: :scheduled, else: :inactive
    end
  end

  @doc "The code's discount on a line of `quantity` units at `unit_price_cents`."
  @spec line_discount(map(), non_neg_integer(), pos_integer()) :: non_neg_integer()
  def line_discount(%{discount_percent: percent}, unit_price, quantity)
      when is_integer(percent) do
    gross = unit_price * quantity
    min(gross, div(gross * percent + 50, 100))
  end

  def line_discount(%{discount_cents: cents}, unit_price, quantity) when is_integer(cents),
    do: min(unit_price, cents) * quantity

  def line_discount(_code, _unit_price, _quantity), do: 0
end
