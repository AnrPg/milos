defmodule Palee.Fiscal.Domain.EInvoicePolicy do
  @moduledoc """
  When and how a fiscal document is sent over an e-invoicing network
  (Peppol, ADR-250). Pure.

  A submission is an outbox row next to an immutable document:

    * `pending` – waiting for its next attempt (`next_attempt_at`);
    * `sending` – claimed by a worker that submits it; a claim older than
      `claim_timeout_seconds/0` is taken over;
    * `submitted` – the access point took it (`provider_submission_id`);
      its delivery is polled with backoff (a webhook only makes the next
      poll due now);
    * `delivered` – the receiver's access point acknowledged it; final;
    * `rejected` – the access point refused its content or could not
      deliver it; staff fix the cause (e.g. the buyer's Peppol address) and
      retry;
    * `failed` – transient errors for `max_attempts/0` attempts in a row;
    * `uncertain` – the request may have reached the access point but no
      answer came (timeout, dropped connection, or the idempotency GUID was
      already used). It is **never sent again automatically**: staff check
      the provider's portal and retry only if it is not there.

  Waiting for a connection or for valid credentials is a deferral and
  costs no attempt.
  """

  alias Palee.Fiscal.Domain.TransmissionPolicy

  @statuses ~w(pending sending submitted delivered rejected failed uncertain)
  @retryable ~w(rejected failed uncertain)
  @max_attempts 20
  @claim_timeout_seconds 600
  # Seconds before delivery poll n+1 (0-based); polling stops after the last.
  @polls [120, 300, 900, 1_800, 3_600, 10_800, 21_600, 43_200, 86_400, 86_400, 86_400]

  def statuses, do: @statuses
  def max_attempts, do: @max_attempts
  def claim_timeout_seconds, do: @claim_timeout_seconds

  @doc """
  True when the document must go over Peppol: its country's profile names
  Peppol, it is an invoice (or a credit note correcting one), and it has a
  buyer.
  """
  def required?(%{einvoicing: einvoicing}, document) do
    :peppol in einvoicing and document.kind in ["invoice", "credit_note"] and
      is_map(document.buyer) and document.buyer != %{}
  end

  def required?(_profile, _document), do: false

  def retryable?(%{status: status}), do: status in @retryable

  @doc "When delivery poll number `polls` (0-based) runs, or nil to stop polling."
  def next_poll_at(polls, %DateTime{} = now) when is_integer(polls) and polls >= 0 do
    case Enum.at(@polls, polls) do
      nil -> nil
      seconds -> DateTime.add(now, seconds, :second)
    end
  end

  @doc """
  The submission's changes after a submit with network `result`:

    * `{:ok, %{submission_id}}` → submitted, first poll soon;
    * `{:error, {:rejected, errors}}` → rejected;
    * `{:error, {:unauthorized, reason}}` → deferred, connection invalid;
    * `{:error, {:uncertain, reason}}` → uncertain, never resent by itself;
    * any other error → retried with backoff, failed after the last try.
  """
  def submit_outcome(submission, result, %DateTime{} = now) do
    case result do
      {:ok, %{submission_id: id}} when is_binary(id) ->
        %{
          status: "submitted",
          provider_submission_id: id,
          submitted_at: now,
          polls: 0,
          next_attempt_at: next_poll_at(0, now),
          last_error_code: nil,
          last_error_message: nil
        }

      {:error, {:uncertain, reason}} ->
        %{
          status: "uncertain",
          next_attempt_at: nil,
          last_error_code: "uncertain",
          last_error_message: text(reason)
        }

      other ->
        common_outcome(submission, other, now)
    end
  end

  @doc """
  The submission's changes after a delivery poll:

    * `{:ok, :delivered}` → delivered;
    * `{:ok, :in_progress}` → still submitted, next poll later;
    * `{:ok, {:failed, errors}}` → rejected (delivery failed);
    * `{:error, {:unauthorized, reason}}` → polled again after the deferral;
    * any other error → polled again later.
  """
  def poll_outcome(submission, result, %DateTime{} = now) do
    polls = submission.polls + 1

    case result do
      {:ok, :delivered} ->
        %{
          status: "delivered",
          delivered_at: now,
          polls: polls,
          next_attempt_at: nil,
          last_error_code: nil,
          last_error_message: nil
        }

      {:ok, {:failed, errors}} ->
        %{
          status: "rejected",
          polls: polls,
          next_attempt_at: nil,
          last_error_code: "delivery_failed",
          last_error_message: errors_text(errors)
        }

      {:ok, :in_progress} ->
        %{status: "submitted", polls: polls, next_attempt_at: next_poll_at(polls, now)}

      {:error, {:unauthorized, reason}} ->
        %{
          status: "submitted",
          next_attempt_at: TransmissionPolicy.deferred_until(:connection_invalid, now),
          last_error_code: "connection_invalid",
          last_error_message: text(reason)
        }

      {:error, reason} ->
        %{
          status: "submitted",
          polls: polls,
          next_attempt_at: next_poll_at(polls, now) || DateTime.add(now, 86_400, :second),
          last_error_code: "transient",
          last_error_message: text(reason)
        }
    end
  end

  defp common_outcome(submission, result, now) do
    attempts = submission.attempts

    case result do
      {:error, {:rejected, errors}} ->
        %{
          status: "rejected",
          next_attempt_at: nil,
          last_error_code: errors |> List.first(%{}) |> Map.get(:code) |> code(),
          last_error_message: errors_text(errors)
        }

      {:error, {:unauthorized, reason}} ->
        %{
          status: "pending",
          attempts: max(attempts - 1, 0),
          next_attempt_at: TransmissionPolicy.deferred_until(:connection_invalid, now),
          last_error_code: "connection_invalid",
          last_error_message: text(reason)
        }

      {:error, reason} ->
        if attempts >= @max_attempts do
          %{
            status: "failed",
            next_attempt_at: nil,
            last_error_code: "transient",
            last_error_message: text(reason)
          }
        else
          %{
            status: "pending",
            next_attempt_at: TransmissionPolicy.next_attempt_at(max(attempts, 1), now),
            last_error_code: "transient",
            last_error_message: text(reason)
          }
        end
    end
  end

  @doc "A deferral before sending: back to pending without spending an attempt."
  def deferral(submission, reason, %DateTime{} = now),
    do: TransmissionPolicy.deferral(submission, reason, now)

  @doc """
  Staff retry. A refused or failed submission is sent with a new
  idempotency GUID (the access point saw the old one); an uncertain one
  keeps its GUID, so if the first request did arrive the access point
  refuses the copy instead of delivering it twice.
  """
  def retry(%{status: "uncertain"}, %DateTime{} = now),
    do: %{status: "pending", attempts: 0, next_attempt_at: now, last_error_code: nil}

  def retry(_submission, %DateTime{} = now) do
    %{
      status: "pending",
      attempts: 0,
      polls: 0,
      next_attempt_at: now,
      idempotency_guid: Ecto.UUID.generate(),
      provider_submission_id: nil,
      submitted_at: nil,
      last_error_code: nil
    }
  end

  @doc "The outcome name recorded on the attempt row."
  def attempt_outcome(:submit, {:ok, _}), do: "submitted"
  def attempt_outcome(:status, {:ok, :delivered}), do: "delivered"
  def attempt_outcome(:status, {:ok, :in_progress}), do: "in_progress"
  def attempt_outcome(:status, {:ok, {:failed, _}}), do: "rejected"
  def attempt_outcome(_operation, {:error, {:rejected, _}}), do: "rejected"
  def attempt_outcome(_operation, {:error, {:unauthorized, _}}), do: "unauthorized"
  def attempt_outcome(_operation, {:error, {:uncertain, _}}), do: "uncertain"
  def attempt_outcome(_operation, {:error, _}), do: "transient"

  defp errors_text(errors) when is_list(errors) do
    errors
    |> Enum.map_join("; ", fn
      %{code: code, message: message} -> "#{code}: #{message}"
      %{message: message} -> to_string(message)
      other -> inspect(other)
    end)
    |> String.slice(0, 1_000)
  end

  defp errors_text(other), do: text(other)

  defp text(reason) when is_binary(reason), do: String.slice(reason, 0, 1_000)
  defp text(reason), do: reason |> inspect() |> String.slice(0, 1_000)

  defp code(nil), do: "rejected"
  defp code(code), do: code |> to_string() |> String.slice(0, 40)
end
