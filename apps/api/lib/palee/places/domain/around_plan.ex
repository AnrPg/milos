defmodule Palee.Places.Domain.AroundPlan do
  @moduledoc """
  What a Γύρω μου filter asks of each kind (ADR-154), given who is looking:

  * **Kinds and cost.** With no cost chosen every selected kind shows.
    «Δωρεάν» keeps free events and open clubs (always free); a maximum
    price keeps events up to it (and clubs); «Δοκιμαστικό» keeps boxes that
    take trial guests. Posts have no cost and ignore it.
  * **Tags** (discipline, audience, language, amenities) narrow every kind
    through the host box's published profile; a person's post has no host
    and drops out when any tag is chosen.
  * **When** narrows events only.
  * **Boxes for people who already have a gym** (plan §5a): they are not a
    category but one collapsed line («Άλλα box στην περιοχή»), never pins
    on the map and never in alerts; the person's own gyms never show.
  * **Posts** are the last 60 days.
  """

  alias Palee.Places.Domain.{AroundFilter, WhenWindow}

  @post_days 60
  @section_limit 5
  @max_section_limit 10
  @page_limit 20
  @max_page_limit 50
  @pins_limit 200

  def section_limit(nil), do: @section_limit
  def section_limit(limit) when is_integer(limit), do: limit |> max(1) |> min(@max_section_limit)
  def section_limit(_limit), do: @section_limit

  def page_limit(nil), do: @page_limit
  def page_limit(limit) when is_integer(limit), do: limit |> max(1) |> min(@max_page_limit)
  def page_limit(_limit), do: @page_limit

  def pins_limit, do: @pins_limit

  @doc """
  `viewer` is `%{user_id, organization_ids}` (the gyms the person actively
  belongs to). `purpose` is `:list`, `:pins` or `:alert`.
  """
  def build(%AroundFilter{} = filter, viewer, %DateTime{} = now, purpose \\ :list)
      when purpose in [:list, :pins, :alert] do
    has_gym? = viewer.organization_ids != []

    kinds =
      filter.kinds
      |> Enum.filter(&cost_allows?(&1, filter))
      |> Enum.reject(&(&1 == "boxes" and has_gym? and purpose in [:pins, :alert]))

    %{
      kinds: kinds,
      now: now,
      viewer_id: viewer.user_id,
      windows:
        WhenWindow.windows(filter.when, filter.date_from, filter.date_to, filter.times, now),
      max_price_cents: max_price_cents(filter),
      trial_only: "trial" in filter.cost,
      exclude_ids: viewer.organization_ids,
      since: DateTime.add(now, -@post_days * 86_400, :second),
      disciplines: nil_if_empty(filter.disciplines),
      audiences: nil_if_empty(filter.audiences),
      languages: nil_if_empty(filter.languages),
      amenities: nil_if_empty(filter.amenities),
      boxes_placement: if(has_gym?, do: "collapsed", else: "category"),
      created_after: nil
    }
  end

  @doc "The same plan, counting only what was created after `since` (alerts)."
  def created_after(plan, %DateTime{} = since), do: %{plan | created_after: since}

  defp cost_allows?(_kind, %{cost: [], max_price_cents: nil}), do: true
  defp cost_allows?("posts", _filter), do: true
  defp cost_allows?("boxes", filter), do: "trial" in filter.cost

  defp cost_allows?(kind, filter) when kind in ["events", "clubs"],
    do: "free" in filter.cost or not is_nil(filter.max_price_cents)

  # Events: a maximum price includes free ones; «Δωρεάν» alone means 0.
  defp max_price_cents(%{max_price_cents: max}) when is_integer(max), do: max

  defp max_price_cents(%{cost: cost}) do
    if "free" in cost, do: 0
  end

  defp nil_if_empty([]), do: nil
  defp nil_if_empty(list), do: list
end
