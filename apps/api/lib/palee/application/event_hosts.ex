defmodule Palee.Application.EventHosts do
  @moduledoc """
  «Διοργάνωση ως» (ADR-185 §1–2): who a person can host an event as, and
  creating one as that host.

  * **Hosts.** «Ως εγώ» is always offered; each business (gym or coach)
    where the person holds `manage_events` follows, with the clubs an
    event can go in there.
  * **«Ως εγώ».** The first such event creates the person's one-person
    organiser organisation transparently (they own it; it gets its own club
    and the free organiser plan, nothing else), after the event itself
    has been checked, so a bad form never leaves an empty organisation.
    Their events are open to everyone (and show in Γύρω μου and to their
    followers) or by invitation only; creation is rate limited
    (`HostPolicy`). An address without a pin is geocoded so an open event
    can be found nearby.
  * **As a business.** The same as creating from that club's page.
  """

  alias Palee.Application.{ClubScope, CommunityEvents, TenantDefaults}
  alias Palee.{Community, Facility, Identity, Organizations}

  @doc "The hosts the person can pick, «Ως εγώ» first."
  def hosts(%{user_id: user_id} = context) do
    with {:ok, clubs} <- ClubScope.call(context) do
      account = Identity.find_by_id(user_id)
      own = Organizations.organiser_organization(user_id)

      self_host = %{
        kind: "self",
        id: Community.self_host(),
        organization_id: own && own.id,
        slug: own && own.slug,
        name: account && account.nickname,
        logo_url: account && Map.get(account, :avatar_url),
        clubs: []
      }

      businesses =
        user_id
        |> Organizations.list_memberships()
        |> Organizations.provider_memberships()
        |> Enum.filter(&manages_events?/1)
        |> Enum.map(fn %{organization: organization} = entry ->
          %{
            kind: "business",
            id: organization.id,
            organization_id: organization.id,
            slug: organization.slug,
            name: brand_name(entry) || organization.name,
            logo_url: settings(entry)["brand_logo_url"],
            clubs:
              clubs
              |> Enum.filter(&(&1.organization_id == organization.id and &1.kind in ~w(gym open)))
              |> Enum.map(&%{id: &1.id, name: &1.name, kind: &1.kind})
          }
        end)

      {:ok, %{hosts: [self_host | businesses]}}
    end
  end

  @doc """
  Creates an event as `params[:host]` (`"self"`, the default, or a
  business's organisation id; `club_id` picks the business's club, its gym
  club by default).
  """
  def create(context, params) do
    case Community.parse_event_host(params[:host]) do
      :self -> create_as_self(context, params)
      {:business, organization_id} -> create_as_business(context, organization_id, params)
      {:error, _reason} = error -> error
    end
  end

  # ------------------------------------------------------------------ «Ως εγώ»

  defp create_as_self(%{user_id: user_id} = context, params) do
    params = params |> Community.organiser_event_terms() |> Map.delete(:channel_id)
    account = Map.get(context, :account) || Identity.find_by_id(user_id)

    with %{} <- account || {:error, :forbidden},
         :ok <- precheck(params),
         {:ok, organization, _created?} <- ensure_organiser(account, params),
         {:ok, manager} <- CommunityEvents.manager_context(context, organization.id),
         :ok <- rate_check(manager, params),
         {:ok, club} <- organiser_club(manager),
         {:ok, [first | _] = events} <-
           CommunityEvents.manage_create(manager, club, pin_address(params)),
         {:ok, clubs} <- ClubScope.call(context) do
      [shown] = CommunityEvents.present(context, [first], clubs)
      {:ok, %{event: shown, occurrences: length(events)}}
    end
  end

  # The event is checked before an organisation exists for it.
  defp precheck(params) do
    attrs =
      Community.event_editable_fields()
      |> Enum.filter(&Map.has_key?(params, &1))
      |> Map.new(&{&1, Map.get(params, &1)})

    Community.check_event_attrs(attrs)
  end

  defp ensure_organiser(account, params) do
    name = Community.organiser_name(account.nickname)

    Organizations.ensure_organiser_organization(
      account,
      %{
        name: name,
        timezone: params[:time_zone],
        default_locale: Map.get(account, :locale)
      },
      seed_defaults: TenantDefaults.organiser(name)
    )
  end

  defp rate_check(manager, params) do
    now = DateTime.utc_now()

    manager
    |> Community.event_creation_counts(DateTime.add(now, -1, :day), now)
    |> Community.host_creation_check(occurrences(params))
  end

  defp occurrences(%{repeat_until: %Date{} = until, starts_at: %DateTime{} = starts_at}) do
    weeks = until |> Date.diff(DateTime.to_date(starts_at)) |> div(7)
    min(max(weeks + 1, 1), Community.event_series_max())
  end

  defp occurrences(_params), do: 1

  defp organiser_club(%{organization_id: organization_id} = manager) do
    manager
    |> Community.list_clubs([organization_id])
    |> Enum.find(&(&1.kind == "gym" and is_nil(&1.archived_at)))
    |> case do
      nil -> Community.provision_gym_club(manager)
      club -> {:ok, club}
    end
  end

  # An address without a pin gets one, best effort, so Γύρω μου finds it.
  defp pin_address(%{latitude: lat} = params) when is_number(lat), do: params

  defp pin_address(params) do
    query = [params[:place_name], params[:address]] |> Enum.filter(&is_binary/1) |> Enum.join(", ")

    if is_nil(params[:location_id]) and String.length(String.trim(query)) >= 3 do
      case Facility.search_addresses(query, limit: 1) do
        {:ok, [%{latitude: lat, longitude: lng} | _]} when is_number(lat) and is_number(lng) ->
          Map.merge(params, %{latitude: lat, longitude: lng})

        _none ->
          params
      end
    else
      params
    end
  end

  # ------------------------------------------------------------------ as a business

  defp create_as_business(context, organization_id, params) do
    with {:ok, clubs} <- ClubScope.call(context),
         %{} = club <- business_club(clubs, organization_id, params[:club_id]) ||
           {:error, :not_found},
         do: CommunityEvents.create(context, club.id, params)
  end

  defp business_club(clubs, organization_id, nil),
    do: Enum.find(clubs, &(&1.organization_id == organization_id and &1.kind == "gym"))

  defp business_club(clubs, organization_id, club_id),
    do: Enum.find(clubs, &(&1.organization_id == organization_id and &1.id == club_id))

  # ------------------------------------------------------------------ internals

  defp manages_events?(%{membership: membership} = entry) do
    roles = Map.get(membership, :roles) || [membership.role]

    roles
    |> Organizations.capabilities_for(
      Map.get(membership, :coach_scope),
      role_grants(entry)
    )
    |> Map.has_key?(Community.event_capability())
  end

  defp role_grants(entry) do
    case settings(entry)["role_grants"] do
      grants when is_map(grants) -> grants
      _none -> %{}
    end
  end

  defp settings(%{settings: %{settings: settings}}) when is_map(settings), do: settings
  defp settings(_entry), do: %{}

  defp brand_name(entry) do
    case settings(entry)["brand_name"] do
      name when is_binary(name) and name != "" -> String.trim(name)
      _none -> nil
    end
  end
end
