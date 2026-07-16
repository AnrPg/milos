defmodule MilosTraining.Finance.Domain.MembershipLifecycle do
  @manual_statuses ["cancelled", "paused"]
  @date_driven_statuses ["active", "trial", "expiring", "expired"]
  @expiring_window_days 30

  def derive_status(status, starts_on, expires_on, %Date{} = today) do
    starts_on = parse_date(starts_on)
    expires_on = parse_date(expires_on)

    cond do
      status in @manual_statuses ->
        status

      expires_on && Date.compare(expires_on, today) == :lt ->
        "expired"

      (status in @date_driven_statuses and expires_on) &&
          Date.diff(expires_on, today) <= @expiring_window_days ->
        "expiring"

      status == "expired" ->
        if starts_on && Date.compare(starts_on, today) == :gt, do: "trial", else: "active"

      true ->
        status || "trial"
    end
  end

  def active_for_summary?(status, expires_on, %Date{} = today) do
    expires_on = parse_date(expires_on)

    status in ["active", "trial", "expiring", "comped"] and
      (is_nil(expires_on) or Date.compare(expires_on, today) != :lt)
  end

  defp parse_date(%Date{} = date), do: date
  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp parse_date(_value), do: nil
end
