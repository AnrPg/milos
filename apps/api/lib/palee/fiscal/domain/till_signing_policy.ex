defmodule Palee.Fiscal.Domain.TillSigningPolicy do
  @moduledoc """
  When and how a receipt is signed by the cash-register security device
  of its country (ADR-251): the TSE in Germany (KassenSichV, §146a AO),
  the signature creation unit in Austria (RKSV). Pure.

  A signature is an outbox row next to an immutable document:

    * `pending` – waiting for its next attempt;
    * `sending` – claimed by a worker; a claim older than
      `claim_timeout_seconds/0` becomes `uncertain` and is read back;
    * `signed` – the device signed it; final;
    * `uncertain` – the request may have reached the device but no answer
      came. The next attempt only **reads** the transaction back
      (`lookup`); it is signed again only once the device says it does not
      have it;
    * `device_failed` – the device could not sign it. Germany: a receipt
      not signed within `outage_seconds/0` of its issue is recorded as a TSE
      failure and printed as such (AEAO zu §146a); a signature hours
      later would misstate when the sale happened. Austria: fiskaly
      reported a signature creation unit outage and the receipt carries
      "Sicherheitseinrichtung ausgefallen" (RKSV §17); fiskaly clears the
      fault with its own receipt;
    * `rejected` – the device refused the content;
    * `failed` – transient errors for `max_attempts/0` attempts in a row.

  In Austria receipts the device could not be reached for stay queued
  until fiskaly answers (fiskaly SIGN AT asks the till to queue them); they
  are printed with "Sicherheitseinrichtung ausgefallen" meanwhile.

  In France (fiskaly SIGN FR, ADR-266) receipts also stay queued until
  fiskaly answers; one sent `outage_seconds/0` or more after its issue is
  flagged `offline` (fiskaly records it as issued during an outage). The
  receipt itself is already secured by Palee's own journal (ADR-242) the
  moment it is issued.

  Waiting for a connection is a deferral and costs no attempt.
  """

  alias Palee.Fiscal.Domain.TransmissionPolicy

  @statuses ~w(pending sending signed uncertain device_failed rejected failed)
  @retryable ~w(rejected failed device_failed uncertain)
  @max_attempts 20
  @claim_timeout_seconds 300
  @outage_seconds 300
  @lookup_after_seconds 30

  def statuses, do: @statuses
  def max_attempts, do: @max_attempts
  def claim_timeout_seconds, do: @claim_timeout_seconds
  def outage_seconds, do: @outage_seconds

  @doc "`\"tse\"`, `\"rksv\"`, `\"sign_fr\"` or nil: the device of a country profile."
  def device(%{till_device: :tse}), do: "tse"
  def device(%{till_device: :rksv}), do: "rksv"
  def device(%{till_device: :sign_fr}), do: "sign_fr"
  def device(_profile), do: nil

  @doc "True when a receipt is sent after the outage window (France: flagged offline)."
  def offline?(%DateTime{} = now, %DateTime{} = issued_at),
    do: DateTime.diff(now, issued_at, :second) >= @outage_seconds

  def offline?(_now, _issued_at), do: false

  @till_methods ~w(cash card)

  @doc "Payment methods of money taken at the till (the desk): cash and card, a terminal's too."
  def till_methods, do: @till_methods

  @doc """
  True when the document must be signed: its country has a till device
  and it records money taken at the till (ADR-251, update 2026-10-29):

    * a receipt;
    * an invoice paid at the till (`payment_method` cash or card, a card
      terminal's too). DSFinV-K's process type `Beleg` covers every
      transaction closed at the till, "neben der Rechnung (§ 14 UStG) auch
      Gutschriften und Korrekturrechnungen"; in Austria a cash sale
      (Barumsatz, § 131b (1) Z 3 BAO) includes card payments;
    * a credit note correcting a document signed by these rules
      (`original` is the corrected document, or only its kind).

  An invoice paid later by bank transfer or online, or with no payment
  method, is not a till transaction and is not signed.

  France (`sign_fr`, ADR-266) signs receipts and their credit notes only:
  an invoice paid at the till, and its credit note, stay secured by
  Palee's own journal (ADR-242) until fiskaly confirms how SIGN FR records
  invoices.
  """
  def required?(profile, document, original \\ nil) do
    case device(profile) do
      nil -> false
      "sign_fr" -> receipt_only?(document, original)
      _device -> till_transaction?(document, original)
    end
  end

  defp receipt_only?(%{kind: "receipt"}, _original), do: true
  defp receipt_only?(%{kind: "credit_note"}, "receipt"), do: true
  defp receipt_only?(%{kind: "credit_note"}, %{kind: "receipt"}), do: true
  defp receipt_only?(_document, _original), do: false

  defp till_transaction?(%{kind: "receipt"}, _original), do: true

  defp till_transaction?(%{kind: "invoice"} = document, _original),
    do: Map.get(document, :payment_method) in @till_methods

  defp till_transaction?(%{kind: "credit_note"}, original) when is_binary(original),
    do: original == "receipt"

  defp till_transaction?(%{kind: "credit_note"}, %{kind: kind} = original)
       when kind in ["receipt", "invoice"],
       do: till_transaction?(original, nil)

  defp till_transaction?(_document, _original), do: false

  def retryable?(%{status: status}), do: status in @retryable

  @doc """
  The signature's changes after a sign or lookup with device `result`:

    * `{:ok, signature}` → signed (or `device_failed` when the device says
      its signing unit is out, `signature.device_failed`);
    * `{:error, :not_found}` (lookup) → pending, signed again now;
    * `{:error, {:rejected, errors}}` → rejected;
    * `{:error, {:unauthorized, reason}}` → deferred, connection invalid;
    * `{:error, {:uncertain, reason}}` → uncertain, read back soon;
    * any other error → retried with backoff, failed after the last try.

  A German receipt that is not signed `outage_seconds/0` after its issue
  becomes `device_failed` instead of being retried.
  """
  def outcome(signature, result, %DateTime{} = now, opts \\ []) do
    case result do
      {:ok, %{device_failed: true} = data} ->
        data
        |> signed_fields()
        |> Map.merge(%{
          status: "device_failed",
          failed_at: now,
          next_attempt_at: nil,
          last_error_code: "device_failed",
          last_error_message: data[:hint]
        })

      {:ok, data} ->
        data
        |> signed_fields()
        |> Map.merge(%{
          status: "signed",
          signed_at: now,
          next_attempt_at: nil,
          last_error_code: nil,
          last_error_message: nil
        })

      {:error, :not_found} ->
        late_or(signature, now, opts, %{
          status: "pending",
          attempts: max(signature.attempts - 1, 0),
          next_attempt_at: now,
          last_error_code: "not_found"
        })

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
          attempts: max(signature.attempts - 1, 0),
          next_attempt_at: TransmissionPolicy.deferred_until(:connection_invalid, now),
          last_error_code: "connection_invalid",
          last_error_message: text(reason)
        }

      {:error, {:uncertain, reason}} ->
        %{
          status: "uncertain",
          next_attempt_at: DateTime.add(now, @lookup_after_seconds, :second),
          last_error_code: "uncertain",
          last_error_message: text(reason)
        }

      {:error, reason} ->
        cond do
          signature.attempts >= @max_attempts ->
            %{
              status: "failed",
              next_attempt_at: nil,
              last_error_code: "transient",
              last_error_message: text(reason)
            }

          true ->
            late_or(signature, now, opts, %{
              status: "pending",
              next_attempt_at:
                TransmissionPolicy.next_attempt_at(max(signature.attempts, 1), now),
              last_error_code: "transient",
              last_error_message: text(reason)
            })
        end
    end
  end

  # Germany: past the outage window a receipt is recorded as a TSE failure.
  defp late_or(%{device: "tse", kind: "receipt"}, now, opts, otherwise) do
    case opts[:issued_at] do
      %DateTime{} = issued_at ->
        if DateTime.diff(now, issued_at, :second) >= @outage_seconds,
          do: tse_failure(now, otherwise[:last_error_message]),
          else: otherwise

      _unknown ->
        otherwise
    end
  end

  defp late_or(_signature, _now, _opts, otherwise), do: otherwise

  @doc "A German receipt recorded as a TSE failure (no signature)."
  def tse_failure(%DateTime{} = now, message \\ nil) do
    %{
      status: "device_failed",
      failed_at: now,
      next_attempt_at: nil,
      last_error_code: "device_failed",
      last_error_message: message
    }
  end

  @doc """
  What a worker does with a claimed row: `:lookup` for an uncertain one
  (read back, never sent blindly), `:fail` for a German receipt past its
  outage window, `:sign` otherwise.
  """
  def operation(%{status: "uncertain"}, _now, _issued_at), do: :lookup

  def operation(%{device: "tse", kind: "receipt"}, %DateTime{} = now, %DateTime{} = issued_at) do
    if DateTime.diff(now, issued_at, :second) >= @outage_seconds, do: :fail, else: :sign
  end

  def operation(_signature, _now, _issued_at), do: :sign

  defp signed_fields(data) do
    Map.take(data, [
      :transaction_number,
      :signature_counter,
      :signature_value,
      :signature_algorithm,
      :time_format,
      :started_at_device,
      :finished_at_device,
      :unit_serial,
      :register_serial,
      :receipt_number,
      :qr_code_data
    ])
  end

  @doc "A deferral: back to pending without spending an attempt."
  def deferral(signature, reason, %DateTime{} = now),
    do: TransmissionPolicy.deferral(signature, reason, now)

  @doc """
  Staff retry. An uncertain row is read back first; any other row is
  signed again with the same external id, so a device that did sign it
  answers with the existing transaction instead of a second one.
  """
  def retry(%{status: "uncertain"}, %DateTime{} = now),
    do: %{status: "uncertain", attempts: 0, next_attempt_at: now}

  def retry(_signature, %DateTime{} = now),
    do: %{status: "pending", attempts: 0, next_attempt_at: now, failed_at: nil}

  @doc "The outcome name recorded on the attempt row."
  def attempt_outcome({:ok, %{device_failed: true}}), do: "device_failed"
  def attempt_outcome({:ok, _signature}), do: "signed"
  def attempt_outcome({:error, :not_found}), do: "not_found"
  def attempt_outcome({:error, {:rejected, _}}), do: "rejected"
  def attempt_outcome({:error, {:unauthorized, _}}), do: "unauthorized"
  def attempt_outcome({:error, {:uncertain, _}}), do: "uncertain"
  def attempt_outcome({:error, _reason}), do: "transient"

  defp errors_text(errors) when is_list(errors) do
    errors
    |> Enum.map_join("; ", fn
      %{code: code, message: message} -> "#{code}: #{message}"
      other -> inspect(other)
    end)
    |> String.slice(0, 1_000)
  end

  defp text(nil), do: nil
  defp text(reason) when is_binary(reason), do: String.slice(reason, 0, 1_000)
  defp text(reason), do: reason |> inspect() |> String.slice(0, 1_000)

  defp code(nil), do: "rejected"
  defp code(code), do: code |> to_string() |> String.slice(0, 40)
end
