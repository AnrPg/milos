defmodule Palee.Fiscal.Domain.ConnectionCheckPolicy do
  @moduledoc """
  «Δοκιμή σύνδεσης» (ADR-273), pure rules.

  A box's fiscal connections are named by kind: `mydata` and `registry`
  (Greece, AADE), `tse` (DE), `rksv` (AT), `sign_fr` (FR) and `peppol`
  (BE, fiskaly E-INVOICE). `kinds/1` says which ones the box's country
  asks for, in the order the screen lists them.

  A check answers with one of three outcomes:

    * `:ok` – the provider accepted the credentials and knows the unit,
      register or System Palee uses;
    * `{:invalid, code}` – a definite refusal: the connection is marked
      `invalid` until a check passes or it is saved again;
    * `{:unreachable, code}` – the connection could not be checked (network,
      outage, AADE's quota, or the business's own ΑΦΜ missing or unknown to
      the registry, which says nothing about the credentials): the
      connection keeps its status and is checked again sooner.

  `code` is a stable error code (`error_codes/0`) the screens turn into a
  plain message in the viewer's language; free text from a provider is
  never shown.
  """

  @kinds ~w(mydata registry tse rksv sign_fr peppol)
  @till_kinds ~w(tse rksv sign_fr)

  @error_codes ~w(credentials_rejected credentials_missing unit_not_found unit_not_ready
                  system_not_found tax_id_missing tax_id_not_found siren_missing limit_reached
                  unreachable provisioning_failed provider_retired)

  # A passing check is repeated after about three months.
  @healthy_days 90
  # After a refusal: 1 h, 6 h, 1 day, 3 days, then weekly.
  @invalid_backoff_minutes [60, 360, 1_440, 4_320, 10_080]
  # After an unreachable provider: 15 min, 1 h, 6 h, then daily.
  @unreachable_backoff_minutes [15, 60, 360, 1_440]

  # A staff member's «Δοκιμή σύνδεσης» is refused this soon after the last
  # check. The registry check spends one of the business's AADE look-ups.
  @manual_interval_seconds %{"registry" => 600}
  @default_manual_interval_seconds 30

  def kinds, do: @kinds
  def till_kinds, do: @till_kinds
  def error_codes, do: @error_codes

  @doc "The connection kinds the country profile asks for, in screen order."
  def kinds(%{} = profile) do
    authority = if Map.get(profile, :authority) == :mydata, do: ["mydata", "registry"], else: []

    till =
      case Map.get(profile, :till_device) do
        device when device in [:tse, :rksv, :sign_fr] -> [Atom.to_string(device)]
        _none -> []
      end

    peppol = if :peppol in Map.get(profile, :einvoicing, []), do: ["peppol"], else: []

    authority ++ till ++ peppol
  end

  def kinds(_profile), do: []

  @doc """
  Turns what a port answered into an outcome. Ports answer `{:ok, _}` or
  `{:error, reason}` with their own reasons; this is the one place that
  knows them all.
  """
  def outcome({:ok, _detail}), do: :ok
  def outcome({:error, reason}), do: classify(reason)

  @doc false
  def classify({:unauthorized, :credentials_missing}), do: {:invalid, "credentials_missing"}
  def classify({:unauthorized, _reason}), do: {:invalid, "credentials_rejected"}
  def classify(:credentials_rejected), do: {:invalid, "credentials_rejected"}
  def classify(:credentials_missing), do: {:invalid, "credentials_missing"}
  def classify(:unit_not_found), do: {:invalid, "unit_not_found"}
  def classify(:unit_not_ready), do: {:invalid, "unit_not_ready"}
  def classify(:system_not_found), do: {:invalid, "system_not_found"}
  def classify(:siren_missing), do: {:invalid, "siren_missing"}
  def classify(:provisioning_failed), do: {:invalid, "provisioning_failed"}
  def classify(:provider_retired), do: {:invalid, "provider_retired"}
  # The registry check needs the business's own ΑΦΜ; without it, or when
  # AADE does not know it, the credentials are neither confirmed nor refused
  # (look-ups of other ΑΦΜ keep working): the ΑΦΜ in Στοιχεία τιμολόγησης
  # must be checked.
  def classify(:tax_id_missing), do: {:unreachable, "tax_id_missing"}
  def classify(:not_found), do: {:unreachable, "tax_id_not_found"}
  def classify(:limit_reached), do: {:unreachable, "limit_reached"}

  def classify({:rejected, [%{code: code} | _rest]}) when code in ["system_not_found"],
    do: {:invalid, "system_not_found"}

  def classify({:rejected, _errors}), do: {:invalid, "unit_not_found"}
  def classify(_transient), do: {:unreachable, "unreachable"}

  @doc """
  The connection columns to write after a check with `outcome`, given the
  connection as it was (`status`, `check_failures`).
  """
  def changes(connection, outcome, %DateTime{} = now) do
    failures = Map.get(connection, :check_failures) || 0

    case outcome do
      :ok ->
        %{
          error_code: nil,
          checked_at: now,
          check_failures: 0,
          next_check_at: DateTime.add(now, @healthy_days * 86_400, :second)
        }
        |> Map.merge(recovered_status(connection))

      {:invalid, code} ->
        %{
          status: "invalid",
          error_code: code,
          checked_at: now,
          check_failures: failures + 1,
          next_check_at: later(now, @invalid_backoff_minutes, failures)
        }

      {:unreachable, code} ->
        %{
          error_code: code,
          checked_at: now,
          check_failures: failures + 1,
          next_check_at: later(now, @unreachable_backoff_minutes, failures)
        }
    end
  end

  # A passing check brings an invalid connection back. A till connection
  # still `provisioning` stays so: only saving it finishes the device.
  defp recovered_status(%{status: "invalid"}), do: %{status: "active", last_error: nil}
  defp recovered_status(_connection), do: %{}

  defp later(now, steps, failures) do
    minutes = Enum.at(steps, failures, List.last(steps))
    DateTime.add(now, minutes * 60, :second)
  end

  @doc "True when the connection is due for a scheduled check."
  def due?(%{next_check_at: nil}, _now), do: true

  def due?(%{next_check_at: %DateTime{} = at}, %DateTime{} = now),
    do: DateTime.compare(at, now) != :gt

  def due?(_connection, _now), do: false

  @doc """
  `:ok` or `{:error, :check_too_soon}` for a staff member's check of
  `kind` when the last one was at `checked_at`.
  """
  def manual_allowed?(kind, checked_at, %DateTime{} = now) do
    interval = Map.get(@manual_interval_seconds, kind, @default_manual_interval_seconds)

    if is_nil(checked_at) or DateTime.diff(now, checked_at, :second) >= interval,
      do: :ok,
      else: {:error, :check_too_soon}
  end

  @doc "True when moving `before` → `after_status` should alert the staff."
  def newly_invalid?(before_status, "invalid"), do: before_status != "invalid"
  def newly_invalid?(_before_status, _after_status), do: false
end
