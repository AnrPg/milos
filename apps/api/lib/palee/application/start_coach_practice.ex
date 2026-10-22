defmodule Palee.Application.StartCoachPractice do
  @moduledoc """
  ADR-170 (vision §7.10): an account opens its practice as an independent
  coach. One transaction creates the one-person organization (kind `coach`,
  the account as owner and coach), the tenant defaults, the «Team» club and
  the default coach plan on its trial.
  """

  alias Palee.Application.TenantDefaults
  alias Palee.{Identity, Organizations}

  def call(account, params) when is_map(params) do
    name = params |> value(:name) |> trim()

    with {:ok, name} <- validate_name(name),
         {:ok, timezone} <- timezone(value(params, :timezone)),
         {:ok, locale} <- locale(value(params, :default_locale)),
         {:ok, team_name} <- team_name(value(params, :team_name), name) do
      Organizations.create_coach_practice(
        account,
        %{
          name: name,
          timezone: timezone,
          # ADR-176: the sign-up device's zone is a guess until confirmed.
          timezone_source: timezone && "inferred",
          default_locale: locale
        },
        seed_defaults: TenantDefaults.coach_practice(team_name)
      )
    end
  end

  @doc "«Team Νίκος» from «Νίκος Παπαδόπουλος» when the coach gives no club name."
  def default_team_name(name) do
    first = name |> String.split(~r/\s+/u, trim: true) |> List.first()
    "Team " <> (first || name)
  end

  defp validate_name(name) when is_binary(name) and byte_size(name) > 0 do
    if String.length(name) in 2..120, do: {:ok, name}, else: {:error, :invalid_name}
  end

  defp validate_name(_name), do: {:error, :invalid_name}

  defp team_name(nil, name), do: {:ok, default_team_name(name)}

  defp team_name(value, name) when is_binary(value) do
    case String.trim(value) do
      "" -> {:ok, default_team_name(name)}
      team -> if String.length(team) <= 80, do: {:ok, team}, else: {:error, :invalid_name}
    end
  end

  defp team_name(_value, _name), do: {:error, :invalid_name}

  # ADR-176: no zone leaves it unset; onboarding asks for it.
  defp timezone(zone) when zone in [nil, ""], do: {:ok, nil}

  defp timezone(zone) when is_binary(zone) do
    case DateTime.now(zone) do
      {:ok, _now} -> {:ok, zone}
      _invalid -> {:error, :invalid_timezone}
    end
  end

  defp timezone(_zone), do: {:error, :invalid_timezone}

  defp locale(locale) when is_binary(locale) do
    if locale in Identity.supported_locales(), do: {:ok, locale}, else: {:ok, "el"}
  end

  defp locale(_locale), do: {:ok, "el"}

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value

  defp value(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
