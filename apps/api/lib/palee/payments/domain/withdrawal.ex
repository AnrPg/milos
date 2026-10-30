defmodule Palee.Payments.Domain.Withdrawal do
  @moduledoc """
  The right to withdraw from a service bought online (ADR-248; EU Consumer
  Rights Directive 2011/83 art. 9, 14(3) and 16(a), the EEA, and the UK's
  Consumer Contracts Regulations 2013).

  A member who buys a package online may withdraw within 14 days. Because
  a box's package should start at once, the purchase asks the member to
  request that expressly; on withdrawal they then pay only for the part
  already provided, in proportion (days of the period, or visits of a
  package with a fixed number of visits, whichever is larger).

  The wording is a draft for legal review.
  """

  @days 14
  @version "2026-10-v1"
  @countries ~w(AT BE BG HR CY CZ DK EE FI FR DE GR HU IE IT LV LT LU MT NL PL PT RO SK SI ES SE
                IS LI NO GB)
  @texts %{
    "el" =>
      "Ζητώ να ξεκινήσει το πακέτο αμέσως. Γνωρίζω ότι μπορώ να υπαναχωρήσω μέσα σε 14 ημέρες από την αγορά, πληρώνοντας μόνο το μέρος που χρησιμοποίησα.",
    "en" =>
      "I ask for the package to start now. I understand that I can withdraw within 14 days of buying it and pay only for the part I have used."
  }

  def days, do: @days
  def version, do: @version

  @doc "Whether a business in `country_code` must offer withdrawal from online sales."
  def applies?(country_code) when is_binary(country_code),
    do: String.upcase(country_code) in @countries

  def applies?(_country_code), do: false

  def text(language), do: Map.get(@texts, language, @texts["en"])

  @doc """
  What the purchase keeps: whether withdrawal applies and, when it does,
  the member's express request to start now (required).
  """
  def record(true = _applies, params, %DateTime{} = now) do
    if params[:start_now] == true do
      language = if params[:language] in Map.keys(@texts), do: params[:language], else: "en"

      {:ok,
       %{
         "applies" => true,
         "version" => @version,
         "text_hash" => :sha256 |> :crypto.hash(text(language)) |> Base.encode16(case: :lower),
         "start_now_requested_at" => DateTime.to_iso8601(now),
         "deadline" => now |> DateTime.add(@days * 86_400, :second) |> DateTime.to_iso8601()
       }}
    else
      {:error, :start_now_consent_required}
    end
  end

  def record(false, _params, _now), do: {:ok, %{"applies" => false}}

  @doc "Whether the member may still withdraw (`:ok`) at `now`."
  def open?(%{"applies" => true, "deadline" => deadline}, %DateTime{} = now) do
    case DateTime.from_iso8601(deadline) do
      {:ok, at, _offset} ->
        if DateTime.compare(now, at) == :gt, do: {:error, :withdrawal_period_over}, else: :ok

      _invalid ->
        {:error, :withdrawal_not_available}
    end
  end

  def open?(_withdrawal, _now), do: {:error, :withdrawal_not_available}

  @doc """
  The amount given back: the price less the part already provided.
  `facts`: starts_on, ends_on, visits_used, visits_total.
  """
  def refund_cents(paid_cents, facts, %Date{} = today) when is_integer(paid_cents) do
    fractions =
      [time_fraction(facts, today), visits_fraction(facts)]
      |> Enum.reject(&is_nil/1)

    used = fractions |> Enum.max(fn -> 0.0 end) |> min(1.0) |> max(0.0)
    max(paid_cents - round(paid_cents * used), 0)
  end

  defp time_fraction(%{starts_on: %Date{} = starts, ends_on: %Date{} = ends}, today) do
    total = max(Date.diff(ends, starts), 1)
    max(Date.diff(today, starts), 0) / total
  end

  defp time_fraction(_facts, _today), do: nil

  defp visits_fraction(%{visits_total: total, visits_used: used})
       when is_integer(total) and total > 0 and is_integer(used),
       do: used / total

  defp visits_fraction(_facts), do: nil
end
