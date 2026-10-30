defmodule Palee.Partners.Domain.PhoneCodePolicy do
  @moduledoc """
  The SMS step of the Palee check (ADR-280 §2): one mobile number per
  account, in E.164; a 6-digit code that lives 10 minutes and allows 5
  attempts; at most 3 sends an hour and 10 a day per person. A number is
  only ever shown masked.

  A Greek mobile typed without the country code (`69…`, 10 digits) is read
  as `+30`; `00` stands for `+`.
  """

  @code_digits 6
  @code_minutes 10
  @max_attempts 5
  @sends_per_hour 3
  @sends_per_day 10
  @code_retention_hours 24

  def code_digits, do: @code_digits
  def code_minutes, do: @code_minutes
  def max_attempts, do: @max_attempts
  def sends_per_hour, do: @sends_per_hour
  def sends_per_day, do: @sends_per_day
  def code_retention_hours, do: @code_retention_hours

  @doc "`{:ok, \"+30…\"}` or `{:error, :partner_phone_invalid}`."
  @spec normalize(term()) :: {:ok, String.t()} | {:error, :partner_phone_invalid}
  def normalize(phone) when is_binary(phone) do
    cleaned = String.replace(phone, ~r/[\s().\-\/]/u, "")

    cleaned
    |> international()
    |> validate()
  end

  def normalize(_phone), do: {:error, :partner_phone_invalid}

  defp international("+" <> digits), do: "+" <> digits
  defp international("00" <> digits), do: "+" <> digits
  defp international("69" <> _rest = local) when byte_size(local) == 10, do: "+30" <> local
  defp international(other), do: other

  # E.164: a country code that never starts with 0, at most 15 digits.
  defp validate("+" <> digits = e164) do
    if digits =~ ~r/^[1-9][0-9]{7,14}$/ and greek_mobile_ok?(digits),
      do: {:ok, e164},
      else: {:error, :partner_phone_invalid}
  end

  defp validate(_other), do: {:error, :partner_phone_invalid}

  # A Greek number must be a mobile one (69…, 10 digits after +30).
  defp greek_mobile_ok?("30" <> national), do: national =~ ~r/^69[0-9]{8}$/
  defp greek_mobile_ok?(_digits), do: true

  @doc "The number as shown anywhere: country code and the last 3 digits."
  def mask(nil), do: nil

  def mask("+" <> digits) do
    {head, rest} = String.split_at(digits, min(2, byte_size(digits)))
    tail = String.slice(rest, -3, 3)
    hidden = String.duplicate("•", max(String.length(rest) - String.length(tail), 0))
    "+" <> head <> " " <> hidden <> tail
  end

  def mask(_other), do: "•••"

  @doc "A 6-digit code from a random non-negative integer."
  def code_from(random) when is_integer(random) and random >= 0,
    do: random |> rem(1_000_000) |> Integer.to_string() |> String.pad_leading(@code_digits, "0")

  @doc "A code as typed: 6 digits, spaces ignored."
  def normalize_code(code) when is_binary(code) do
    code = String.replace(code, ~r/\s/u, "")
    if code =~ ~r/^[0-9]{6}$/, do: {:ok, code}, else: {:error, :partner_code_invalid}
  end

  def normalize_code(_code), do: {:error, :partner_code_invalid}

  @doc "When a code sent at `now` expires."
  def expires_at(%DateTime{} = now), do: DateTime.add(now, @code_minutes * 60)

  @doc "Window starts of the send limits: `{hour_ago, day_ago}`."
  def send_windows(%DateTime{} = now),
    do: {DateTime.add(now, -3_600), DateTime.add(now, -86_400)}

  @doc "Codes older than this are deleted by the daily job."
  def retention_cutoff(%DateTime{} = now), do: DateTime.add(now, -@code_retention_hours * 3_600)

  @doc "`:ok` while the person is within both send limits."
  def check_send_rate(sent_last_hour, sent_last_day)
      when is_integer(sent_last_hour) and is_integer(sent_last_day) do
    if sent_last_hour < @sends_per_hour and sent_last_day < @sends_per_day,
      do: :ok,
      else: {:error, :partner_phone_rate_limited}
  end

  @doc """
  Whether a stored code may still be tried: `:ok`, or the error to answer.
  A used, expired or exhausted code is `partner_code_expired` (ask for a new
  one); no code at all is `partner_code_invalid`.
  """
  def check_code(nil, _now), do: {:error, :partner_code_invalid}
  def check_code(%{consumed_at: %DateTime{}}, _now), do: {:error, :partner_code_expired}

  def check_code(%{attempts: attempts}, _now) when attempts >= @max_attempts,
    do: {:error, :partner_code_expired}

  def check_code(%{expires_at: %DateTime{} = expires_at}, %DateTime{} = now) do
    if DateTime.compare(expires_at, now) == :gt, do: :ok, else: {:error, :partner_code_expired}
  end

  @doc "The text of the SMS: the code only, readable in every language."
  def sms_body(code), do: "Palee: #{code} (#{@code_minutes} min)"
end
