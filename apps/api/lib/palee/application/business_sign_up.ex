defmodule Palee.Application.BusinessSignUp do
  @moduledoc """
  ADR-184: the «Επαγγελματικός λογαριασμός» step of sign-up. A just
  registered account opens its gym or independent-coach practice in demo
  mode, with the tenant defaults (ADR-133; a coach's club is «Team <first
  name>», ADR-170), and files the activation request the platform team
  answers with an activation link. All in one transaction.

  Only during sign-up (`BusinessAccounts.signing_up?/2`, 30 minutes after
  registering): an older account files a conversion request instead
  (`Application.BusinessRequests`).
  """

  alias Palee.Application.{StartCoachPractice, TenantDefaults}
  alias Palee.{BusinessAccounts, Identity, Organizations}

  def call(account, params, now \\ DateTime.utc_now()) when is_map(params) do
    with :ok <- signing_up(account, now),
         {:ok, details} <- BusinessAccounts.normalize_request_details(params),
         {:ok, timezone} <- timezone(value(params, :timezone)),
         locale = locale(value(params, :default_locale)) do
      create(account, details, timezone, locale)
    end
  end

  @doc "Creates the demo business for `account` and queues its activation request."
  def create(account, details, timezone \\ nil, locale \\ "el") do
    BusinessAccounts.transaction(fn ->
      with {:ok, organization} <-
             Organizations.create_business_account(
               account,
               details.business_kind,
               %{
                 name: details.business_name,
                 timezone: timezone,
                 timezone_source: timezone && "inferred",
                 default_locale: locale
               },
               seed_defaults: defaults(details)
             ),
           {:ok, _request} <-
             BusinessAccounts.file_request(account, "activation", details, organization.id) do
        {:ok, organization}
      end
    end)
  end

  defp defaults(%{business_kind: "coach", business_name: name}),
    do: TenantDefaults.coach_practice(StartCoachPractice.default_team_name(name))

  defp defaults(_gym), do: &TenantDefaults.call/1

  defp signing_up(%{inserted_at: registered_at}, now) do
    if BusinessAccounts.signing_up?(registered_at, now),
      do: :ok,
      else: {:error, :business_signup_closed}
  end

  defp signing_up(_account, _now), do: {:error, :business_signup_closed}

  defp timezone(zone) when zone in [nil, ""], do: {:ok, nil}

  defp timezone(zone) when is_binary(zone) do
    case DateTime.now(zone) do
      {:ok, _now} -> {:ok, zone}
      _invalid -> {:error, :invalid_timezone}
    end
  end

  defp timezone(_zone), do: {:error, :invalid_timezone}

  defp locale(locale) when is_binary(locale) do
    if locale in Identity.supported_locales(), do: locale, else: "el"
  end

  defp locale(_locale), do: "el"

  defp value(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
