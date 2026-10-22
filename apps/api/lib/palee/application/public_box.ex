defmodule Palee.Application.PublicBox do
  @moduledoc """
  ADR-142 (P2-M2): the public box page, `/b/:slug`, readable without an
  account. A slug or any of its aliases resolves only for an active gym that
  published its page; everything shown comes from the published snapshot
  (never the draft), its photos, the gym's open locations, the classes of a
  window (read-only, no bookings) and the posts staff made public.

  Reads run in the gym's own scope (`%{organization_id: ...}`), which sees
  every row of that gym, so each function projects only public fields.
  """

  alias Palee.Application.{MediaUrls, OpenClubs, PostPresenter, Trials}
  alias Palee.{Community, Facility, Identity, Media, Organizations, Scheduling}

  @max_window_days 31

  @doc "The page: who the gym is, its «Σχετικά» and its locations."
  def get(slug) do
    with {:ok, box, context} <- resolve(slug) do
      profile = Organizations.get_public_profile(context)
      snapshot = (profile && profile.published_snapshot) || %{}

      {:ok,
       %{
         box: box,
         profile:
           context
           |> present_profile(snapshot)
           |> Map.put(:coaches, coaches(context, snapshot["coach_ids"] || [])),
         published_at: profile && profile.published_at,
         followers_count: box_followers(box.organization_id),
         time_zone: Organizations.organization_timezone(box.organization_id),
         open_clubs: OpenClubs.for_box(context),
         locations:
           context
           |> Facility.list_locations()
           |> Enum.filter(&is_nil(Map.get(&1, :archived_at)))
           |> Enum.map(&present_location/1)
       }}
    end
  end

  @doc """
  Classes between `start_at` and `end_at` (ISO 8601, at most #{@max_window_days}
  days; default the next 7 days), without bookings or member data.
  """
  def schedule(slug, viewer_id \\ nil, params) do
    with {:ok, box, context} <- resolve(slug),
         {:ok, start_at, end_at} <- window(params) do
      slots =
        Scheduling.get_calendar_week(context, %{
          start_at: start_at,
          end_at: end_at,
          class_type_ids: []
        })

      coaches =
        slots
        |> Enum.map(&Map.get(&1, :coach_user_id))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> Identity.list_by_ids()
        |> Map.new(&{&1.id, %{id: &1.id, nickname: &1.nickname, avatar_url: &1.avatar_url}})

      # ADR-144: what a visitor may ask for (nil for members and when the
      # owner hasn't opened trials).
      offer = Trials.offer(box.organization_id, viewer_id, slots)
      seats = (offer && offer.seats) || %{}

      {:ok,
       %{
         box: box,
         start_at: start_at,
         end_at: end_at,
         time_zone: Organizations.organization_timezone(box.organization_id),
         trial_offer: offer && Map.delete(offer, :seats),
         slots:
           Enum.map(slots, fn slot ->
             slot |> present_slot(coaches) |> Map.put(:trial_seats, Map.get(seats, slot.id))
           end)
       }}
    end
  end

  @doc "Posts staff made public, newest first, keyset-paged."
  def posts(slug, viewer_id, params) do
    with {:ok, box, context} <- resolve(slug),
         {:ok, before} <- Community.decode_feed_cursor(params[:cursor] || params["cursor"]) do
      limit = 20

      posts =
        Community.list_public_posts(context, [box.organization_id], viewer_id, %{
          before: before,
          limit: limit + 1
        })

      {page, rest} = Enum.split(posts, limit)

      {:ok,
       %{
         box: box,
         posts: PostPresenter.public_box_posts(page, [box]),
         next_cursor:
           if(rest != [] and page != [], do: Community.encode_feed_cursor(List.last(page)))
       }}
    end
  end

  @doc """
  A published box's card (ADR-156 invite page, link previews): cover photo,
  disciplines and the neighbourhood of its first location. Nil when the box
  never published.
  """
  def card(%{organization_id: _} = context) do
    case Organizations.get_public_profile(context) do
      %{published_at: %DateTime{}, published_snapshot: snapshot} when is_map(snapshot) ->
        profile = present_profile(context, snapshot)

        location =
          context
          |> Facility.list_locations()
          |> Enum.find(&is_nil(Map.get(&1, :archived_at)))

        %{
          cover: profile.cover,
          disciplines: profile.disciplines,
          neighbourhood: location && Map.get(location, :neighbourhood)
        }

      _unpublished ->
        nil
    end
  end

  @doc "The public face of published gyms by id (followed boxes, feed origins)."
  def boxes(organization_ids), do: Organizations.public_boxes(organization_ids)

  @doc "A published box by slug or alias: `{:ok, public_box, %{organization_id: ...}}`."
  def resolve(slug) do
    with %{organization_id: id} <- Organizations.public_box_by_slug(slug),
         [box] <- Organizations.public_boxes([id]) do
      {:ok, box, %{organization_id: id}}
    else
      _missing -> {:error, :not_found}
    end
  end

  defp box_followers(organization_id),
    do:
      "organization"
      |> Community.follower_counts([organization_id])
      |> Map.get(organization_id, 0)

  defp present_profile(context, snapshot) do
    cover_id = snapshot["cover_photo_id"]
    photo_ids = snapshot["photo_ids"] || []

    by_id =
      context
      |> Media.list(:tenant, Enum.reject([cover_id | photo_ids], &is_nil/1))
      |> then(&MediaUrls.present_all(context, &1))
      |> Map.new(&{&1.id, Map.take(&1, [:id, :url, :width, :height])})

    %{
      about: snapshot["about"],
      disciplines: snapshot["disciplines"] || [],
      audiences: snapshot["audiences"] || [],
      amenities: snapshot["amenities"] || [],
      services: snapshot["services"] || [],
      languages: snapshot["languages"] || [],
      cover: cover_id && by_id[cover_id],
      photos: photo_ids |> Enum.map(&by_id[&1]) |> Enum.reject(&is_nil/1)
    }
  end

  # Board 4 Q4: the coaches the owner picked who are still on staff, with the
  # class types they teach over the next four weeks.
  defp coaches(_context, []), do: []

  defp coaches(context, ids) do
    staff = context.organization_id |> Organizations.list_staff() |> MapSet.new(& &1.user_id)
    ids = Enum.filter(ids, &MapSet.member?(staff, &1))
    start_at = DateTime.utc_now() |> DateTime.truncate(:second)

    teaches =
      context
      |> Scheduling.get_calendar_week(%{
        start_at: start_at,
        end_at: DateTime.add(start_at, 28 * 86_400, :second),
        class_type_ids: []
      })
      |> Enum.group_by(&Map.get(&1, :coach_user_id), &class_type_name/1)

    people = ids |> Identity.list_by_ids() |> Map.new(&{&1.id, &1})

    Enum.flat_map(ids, fn id ->
      case people[id] do
        nil ->
          []

        person ->
          [
            %{
              id: id,
              nickname: person.nickname,
              avatar_url: Map.get(person, :avatar_url),
              class_types: teaches |> Map.get(id, []) |> Enum.reject(&is_nil/1) |> Enum.uniq()
            }
          ]
      end
    end)
  end

  defp class_type_name(slot) do
    case Map.get(slot, :class_type) do
      %{name: name} -> name
      _none -> slot.name
    end
  end

  defp present_location(location) do
    Map.take(location, [
      :id,
      :name,
      :address,
      :neighbourhood,
      :city,
      :country_code,
      :latitude,
      :longitude,
      :opening_hours,
      :accessibility
    ])
  end

  defp present_slot(slot, coaches) do
    class_type = Map.get(slot, :class_type)

    %{
      id: slot.id,
      name: slot.name,
      scheduled_at: slot.scheduled_at,
      duration_minutes: slot.duration_minutes,
      capacity: slot.capacity,
      spots_remaining: slot.spots_remaining,
      location_id: Map.get(slot, :location_id),
      coach: Map.get(coaches, Map.get(slot, :coach_user_id)),
      class_type:
        class_type &&
          %{
            id: class_type.id,
            name: class_type.name,
            level: Map.get(class_type, :level),
            audiences: Map.get(class_type, :audiences) || []
          }
    }
  end

  defp window(params) do
    start_param = params[:start_at] || params["start_at"]
    end_param = params[:end_at] || params["end_at"]

    case {start_param, end_param} do
      {nil, nil} ->
        start_at = DateTime.utc_now() |> DateTime.truncate(:second)
        {:ok, start_at, DateTime.add(start_at, 7 * 86_400, :second)}

      {start_param, end_param} ->
        with {:ok, start_at} <- datetime(start_param),
             {:ok, end_at} <- datetime(end_param),
             true <- DateTime.compare(end_at, start_at) == :gt || {:error, :bad_request},
             true <-
               DateTime.diff(end_at, start_at) <= @max_window_days * 86_400 ||
                 {:error, :bad_request} do
          {:ok, start_at, end_at}
        end
    end
  end

  defp datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _invalid -> {:error, :bad_request}
    end
  end

  defp datetime(_value), do: {:error, :bad_request}
end
