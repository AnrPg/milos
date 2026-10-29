defmodule Palee.Fiscal.Domain.TransmissionPolicy do
  @moduledoc """
  When and how a fiscal document is reported to its tax authority
  (ADR-243). Pure.

  A transmission is an outbox row next to an immutable document:

    * `pending` – waiting for its next attempt (`next_attempt_at`);
    * `sending` – claimed by a worker; a claim older than
      `claim_timeout_seconds/0` is taken over (the worker died);
    * `accepted` – the authority gave it a MARK; final;
    * `rejected` – the authority refused its content (validation); staff
      fix the cause (e.g. the identity) and retry, or credit and reissue;
    * `failed` – transient errors for `max_attempts/0` attempts in a row;
      staff retry once the cause is gone.

  Waiting for something outside the document (no authority connection,
  invalid credentials, a credit note whose invoice has no MARK yet) is a
  deferral: it does not count as an attempt.
  """

  @statuses ~w(pending sending accepted rejected failed)
  @retryable ~w(rejected failed)
  @max_attempts 20
  @claim_timeout_seconds 600
  # Seconds to wait after attempt n (1-based); the last value repeats.
  @backoff [60, 300, 900, 1_800, 3_600, 10_800, 21_600, 43_200, 86_400]
  @defer_seconds %{
    connection_missing: 3_600,
    connection_invalid: 3_600,
    original_not_accepted: 600
  }

  def statuses, do: @statuses
  def max_attempts, do: @max_attempts
  def claim_timeout_seconds, do: @claim_timeout_seconds

  @doc "True when documents of this country profile are reported."
  def required?(%{authority: authority}), do: authority != :none
  def required?(_profile), do: false

  @doc "Staff may send a rejected or failed transmission again."
  def retryable?(%{status: status}), do: status in @retryable

  @doc "When the attempt after `attempts` failed ones should run."
  def next_attempt_at(attempts, %DateTime{} = now) when is_integer(attempts) and attempts >= 1 do
    seconds = Enum.at(@backoff, attempts - 1) || List.last(@backoff)
    DateTime.add(now, seconds, :second)
  end

  @doc "When a deferred transmission should look again."
  def deferred_until(reason, %DateTime{} = now),
    do: DateTime.add(now, Map.get(@defer_seconds, reason, 3_600), :second)

  @doc """
  The transmission's changes after one attempt with gateway `result`:

    * `{:ok, %{mark, uid, authentication_code, qr_url}}` → accepted;
    * `{:error, {:rejected, errors}}` → rejected;
    * `{:error, {:unauthorized, reason}}` → deferred, connection invalid;
    * any other error → retried with backoff, failed after the last try.
  """
  def outcome(transmission, result, %DateTime{} = now) do
    attempts = transmission.attempts

    case result do
      {:ok, receipt} ->
        %{
          status: "accepted",
          mark: receipt[:mark],
          uid: receipt[:uid],
          authentication_code: receipt[:authentication_code],
          qr_url: receipt[:qr_url],
          accepted_at: now,
          next_attempt_at: nil,
          last_error_code: nil,
          last_error_message: nil
        }

      {:error, {:rejected, errors}} ->
        %{
          status: "rejected",
          next_attempt_at: nil,
          last_error_code: errors |> List.first(%{}) |> Map.get(:code) |> to_code(),
          last_error_message: errors |> Enum.map_join("; ", &error_text/1) |> limit()
        }

      {:error, {:unauthorized, reason}} ->
        %{
          status: "pending",
          attempts: max(attempts - 1, 0),
          next_attempt_at: deferred_until(:connection_invalid, now),
          last_error_code: "connection_invalid",
          last_error_message: reason |> inspect() |> limit()
        }

      {:error, reason} ->
        if attempts >= @max_attempts do
          %{
            status: "failed",
            next_attempt_at: nil,
            last_error_code: "transient",
            last_error_message: reason |> inspect() |> limit()
          }
        else
          %{
            status: "pending",
            next_attempt_at: next_attempt_at(attempts, now),
            last_error_code: "transient",
            last_error_message: reason |> inspect() |> limit()
          }
        end
    end
  end

  @doc "A deferral: back to pending without spending an attempt."
  def deferral(transmission, reason, %DateTime{} = now) do
    %{
      status: "pending",
      attempts: max(transmission.attempts - 1, 0),
      next_attempt_at: deferred_until(reason, now),
      last_error_code: Atom.to_string(reason),
      last_error_message: nil
    }
  end

  @doc "Staff retry: pending now, with a fresh attempt budget."
  def retry(%DateTime{} = now),
    do: %{status: "pending", attempts: 0, next_attempt_at: now}

  @doc "The outcome name recorded on the attempt row."
  def attempt_outcome({:ok, _receipt}), do: "accepted"
  def attempt_outcome({:error, {:rejected, _errors}}), do: "rejected"
  def attempt_outcome({:error, {:unauthorized, _reason}}), do: "unauthorized"
  def attempt_outcome({:error, _reason}), do: "transient"

  defp error_text(%{code: code, message: message}), do: "#{code}: #{message}"
  defp error_text(%{message: message}), do: message
  defp error_text(error), do: inspect(error)

  defp to_code(nil), do: "rejected"
  defp to_code(code), do: code |> to_string() |> limit(40)

  defp limit(text, max \\ 1_000), do: String.slice(text, 0, max)
end
