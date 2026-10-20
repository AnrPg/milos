defmodule MilosTraining.Application.WellnessInput do
  @moduledoc """
  Shared reading of wellness requests (ADR-159): when something happened, in
  which zone and on which local day, and the gym it was logged in, if any.
  """

  alias MilosTraining.{Organizations, Wellness}

  @doc """
  `{occurred_at, zone, local_date}` from `occurred_at` (default `now`) and
  `occurred_tz` (default UTC). `counts_at` may move the instant a value
  counts at (a night counts when you wake up).
  """
  def occurrence(params, now, counts_at \\ & &1) do
    now = usec(now)
    zone = param(params, "occurred_tz") || "UTC"

    with true <- Wellness.valid_zone?(zone) || {:error, :unknown_time_zone},
         {:ok, at} <- instant(param(params, "occurred_at"), now),
         :ok <- not_future(at, now) do
      at = counts_at.(at)
      {:ok, on} = Wellness.local_day(at, zone)
      {:ok, %{occurred_at: at, occurred_tz: zone, occurred_on: on}}
    end
  end

  @doc "`now` with microsecond precision, as every wellness timestamp column stores it."
  def usec(%DateTime{microsecond: {us, _precision}} = now), do: %{now | microsecond: {us, 6}}

  @doc "Gym provenance from `organization_slug` (the member must belong to it)."
  def provenance(account, params) do
    case param(params, "organization_slug") do
      slug when is_binary(slug) and slug != "" ->
        case Organizations.resolve_tenant_context(account, slug) do
          {:ok, tenant_context} -> {:ok, tenant_context.organization_id}
          {:error, _reason} -> {:error, :wellness_organization_unavailable}
        end

      _personal ->
        {:ok, nil}
    end
  end

  # Up to 7 days back is a correction; a minute ahead covers clock drift.
  @max_back_days 7
  @drift_seconds 60

  def max_back_days, do: @max_back_days

  defp not_future(at, now) do
    cond do
      DateTime.diff(at, now) > @drift_seconds -> {:error, :occurred_in_future}
      DateTime.diff(now, at, :day) > @max_back_days -> {:error, :occurred_too_long_ago}
      true -> :ok
    end
  end

  defp instant(nil, now), do: {:ok, now}
  defp instant(%DateTime{} = at, _now), do: {:ok, at |> DateTime.shift_zone!("Etc/UTC") |> usec()}

  defp instant(value, _now) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> {:ok, at |> DateTime.shift_zone!("Etc/UTC") |> usec()}
      {:error, _reason} -> {:error, :invalid_occurred_at}
    end
  end

  defp instant(_value, _now), do: {:error, :invalid_occurred_at}

  @doc "The `sections` param (list or comma-separated) of «Διαγραφή όλων» and export."
  def sections(params), do: params |> param("sections") |> split_sections()

  defp split_sections(sections) when is_binary(sections),
    do: sections |> String.split(",", trim: true) |> split_sections()

  defp split_sections([_ | _] = sections) do
    sections = Enum.uniq(sections)

    if Enum.all?(sections, &(&1 in MilosTraining.Wellness.erasable_sections())),
      do: {:ok, sections},
      else: {:error, :unknown_wellness_section}
  end

  defp split_sections(_sections), do: {:error, :unknown_wellness_section}

  @doc "Reads a request key given as a string or an atom."
  def param(params, key) when is_map(params),
    do: MilosTraining.Wellness.Domain.EntryValue.get(params, key)

  def present?(params, key) when is_map(params),
    do:
      Map.has_key?(params, key) or
        Enum.any?(Map.keys(params), &(is_atom(&1) and Atom.to_string(&1) == key))
end
