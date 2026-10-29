defmodule Palee.Payments.Domain.Consent do
  @moduledoc """
  The payer's permission to charge a saved card later (ADR-247; PSD2:
  merchant-initiated transactions after a first payment with strong
  customer authentication).

  The payer agrees on Palee before the first payment, to a text that names
  the business, the purpose and the largest amount per charge. We keep the
  text's version and hash, when, from where (IP, device) and the limit. A
  later charge must stay within the limit and the currency; a higher price
  needs a new consent (a new checkout). The payer can withdraw it any time.

  The wording is a draft for legal review.
  """

  @version "2026-10-v1"
  @texts %{
    "el" =>
      "Επιτρέπω στην επιχείρηση «%{business}» να χρεώνει αυτή την κάρτα για %{purpose}, έως %{max} ανά χρέωση, μέχρι να το ανακαλέσω. Μπορώ να το ανακαλέσω οποτεδήποτε από τις πληρωμές μου.",
    "en" =>
      "I allow %{business} to charge this card for %{purpose}, up to %{max} per charge, until I withdraw this permission. I can withdraw it at any time in my payments."
  }

  def version, do: @version
  def languages, do: Map.keys(@texts)

  @doc "The text shown to the payer."
  def text(language, %{business: business, purpose: purpose, max_amount_cents: max} = terms) do
    @texts
    |> Map.get(language, @texts["en"])
    |> String.replace("%{business}", business)
    |> String.replace("%{purpose}", purpose)
    |> String.replace("%{max}", money(max, terms[:currency]))
  end

  @doc """
  The consent record for a checkout that saves the card, or an error when
  the payer did not agree.
  """
  def record(params, terms, %DateTime{} = now) do
    language = if params[:language] in languages(), do: params[:language], else: "en"

    cond do
      params[:accepted] != true ->
        {:error, :consent_required}

      not (is_integer(terms[:max_amount_cents]) and terms[:max_amount_cents] > 0) ->
        {:error, :invalid_consent_limit}

      true ->
        {:ok,
         %{
           "version" => @version,
           "language" => language,
           "text_hash" => hash(text(language, terms)),
           "accepted_at" => DateTime.to_iso8601(now),
           "ip" => clip(params[:ip], 64),
           "user_agent" => clip(params[:user_agent], 300),
           "max_amount_cents" => terms[:max_amount_cents],
           "currency" => terms[:currency]
         }}
    end
  end

  @doc "Whether a saved card may be charged `amount_cents` in `currency` on `today`."
  def allows?(method, amount_cents, currency, %Date{} = today) do
    cond do
      method.status != "active" -> {:error, :payment_method_inactive}
      method.currency != currency -> {:error, :consent_currency_mismatch}
      amount_cents > method.max_amount_cents -> {:error, :consent_limit_exceeded}
      expired?(method, today) -> {:error, :payment_method_expired}
      true -> :ok
    end
  end

  defp expired?(%{exp_year: year, exp_month: month}, today)
       when is_integer(year) and is_integer(month) and month in 1..12 do
    Date.compare(Date.end_of_month(Date.new!(year, month, 1)), today) == :lt
  end

  defp expired?(_method, _today), do: false

  def hash(text), do: :sha256 |> :crypto.hash(text) |> Base.encode16(case: :lower)

  defp clip(value, max) when is_binary(value), do: String.slice(value, 0, max)
  defp clip(_value, _max), do: nil

  defp money(cents, currency) do
    whole = div(cents, 100)
    part = cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{whole}.#{part} #{currency}"
  end
end
