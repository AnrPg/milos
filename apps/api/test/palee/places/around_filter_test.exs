defmodule Palee.Places.Domain.AroundFilterTest do
  use ExUnit.Case, async: true

  alias Palee.Places.Domain.{AroundFilter, AroundPlan}

  @vocabulary %{
    disciplines: ~w(crossfit hyrox running yoga),
    audiences: ~w(beginners women_only over_40),
    amenities: ~w(showers wheelchair_accessible accessible_restroom)
  }
  @id "0b9d3f1e-6a52-4c8e-9a51-2f3b7c1d8e90"

  test "nothing chosen is the default filter" do
    assert {:ok, filter} = AroundFilter.parse(%{}, @vocabulary)
    assert filter == AroundFilter.default()
    assert filter.radius_km == 3.0
    assert filter.kinds == ~w(events boxes clubs)
    assert AroundFilter.active_count(filter) == 0
    assert {:ok, ^filter} = AroundFilter.parse(nil, @vocabulary)
  end

  test "normalises lists to the vocabulary's order, ids to lower case and the radius to one decimal" do
    assert {:ok, filter} =
             AroundFilter.parse(
               %{
                 "radius_km" => 2.345,
                 "neighbourhood_ids" => [String.upcase(@id), @id],
                 "kinds" => ["posts", "events"],
                 "disciplines" => ["running", "crossfit", "running"],
                 "languages" => ["EN", "el"],
                 "cost" => ["trial", "free"],
                 "times" => ["evening", "morning"],
                 when: "weekend",
                 max_price_cents: 1500
               },
               @vocabulary
             )

    assert filter.radius_km == 2.3
    assert filter.neighbourhood_ids == [@id]
    assert filter.kinds == ~w(events posts)
    assert filter.disciplines == ~w(crossfit running)
    assert filter.languages == ~w(el en)
    assert filter.cost == ~w(free trial)
    assert filter.times == ~w(morning evening)
    assert filter.when == "weekend"
    assert filter.max_price_cents == 1500
    assert AroundFilter.active_count(filter) == 6
  end

  test "the canonical params parse back to the same filter, so saved filters are stable" do
    {:ok, filter} =
      AroundFilter.parse(
        %{
          when: "range",
          date_from: "2026-10-24",
          date_to: "2026-10-25",
          amenities: ["wheelchair_accessible"],
          audiences: ["beginners"]
        },
        @vocabulary
      )

    params = AroundFilter.to_params(filter)
    assert params["v"] == 1
    assert params["date_from"] == "2026-10-24"
    assert {:ok, ^filter} = AroundFilter.parse(params, @vocabulary)

    assert {:ok, ^filter} =
             params |> Jason.encode!() |> Jason.decode!() |> AroundFilter.parse(@vocabulary)
  end

  test "unknown keys are ignored; a newer version is refused" do
    assert {:ok, _filter} = AroundFilter.parse(%{"future_thing" => 1}, @vocabulary)
    assert {:error, [v: _]} = AroundFilter.parse(%{"v" => 2}, @vocabulary)
  end

  test "rejects values outside the rules" do
    for {params, field} <- [
          {%{radius_km: 0.1}, :radius_km},
          {%{radius_km: 51}, :radius_km},
          {%{radius_km: "3"}, :radius_km},
          {%{kinds: []}, :kinds},
          {%{kinds: ["gyms"]}, :kinds},
          {%{disciplines: ["weight_loss"]}, :disciplines},
          {%{audiences: ["men"]}, :audiences},
          {%{languages: ["greek"]}, :languages},
          {%{when: "someday"}, :when},
          {%{when: "range", date_from: "2026-10-24"}, :date_to},
          {%{when: "range", date_from: "2026-10-25", date_to: "2026-10-24"}, :date_to},
          {%{when: "range", date_from: "2026-10-01", date_to: "2026-12-31"}, :date_to},
          {%{cost: ["cheap"]}, :cost},
          {%{max_price_cents: -1}, :max_price_cents},
          {%{max_price_cents: 9.5}, :max_price_cents},
          {%{min_price_cents: -5}, :min_price_cents},
          {%{min_price_cents: 2000, max_price_cents: 1000}, :min_price_cents},
          {%{neighbourhood_ids: ["kypseli"]}, :neighbourhood_ids},
          {%{neighbourhood_ids: Enum.map(1..6, &uuid/1)}, :neighbourhood_ids}
        ] do
      assert {:error, [{^field, _message}]} = AroundFilter.parse(params, @vocabulary),
             "#{inspect(params)} should fail on #{field}"
    end

    assert {:error, [filter: _]} = AroundFilter.parse("weekend", @vocabulary)
  end

  describe "the plan" do
    @now ~U[2026-10-21 10:00:00Z]
    @member %{user_id: @id, organization_ids: ["11111111-1111-1111-1111-111111111111"]}
    @visitor %{user_id: @id, organization_ids: []}

    defp plan(params, viewer \\ @visitor, purpose \\ :list) do
      {:ok, filter} = AroundFilter.parse(params, @vocabulary)
      AroundPlan.build(filter, viewer, @now, purpose)
    end

    test "with no cost every selected kind shows" do
      assert plan(%{kinds: ~w(events boxes clubs posts)}).kinds == ~w(events boxes clubs posts)
      assert plan(%{}).max_price_cents == nil
      refute plan(%{}).trial_only
    end

    test "free keeps free events and clubs; trial keeps boxes; posts ignore cost" do
      free = plan(%{kinds: ~w(events boxes clubs posts), cost: ["free"]})
      assert free.kinds == ~w(events clubs posts)
      assert free.max_price_cents == 0

      trial = plan(%{kinds: ~w(events boxes clubs posts), cost: ["trial"]})
      assert trial.kinds == ~w(boxes posts)
      assert trial.trial_only

      capped = plan(%{cost: ["free"], max_price_cents: 1500})
      assert capped.kinds == ~w(events clubs)
      assert capped.max_price_cents == 1500
    end

    test "a price range keeps events inside it, clubs only while it starts at free" do
      ranged = plan(%{kinds: ~w(events boxes clubs posts), min_price_cents: 500, max_price_cents: 2000})
      assert ranged.kinds == ~w(events posts)
      assert {ranged.min_price_cents, ranged.max_price_cents} == {500, 2000}

      up_to = plan(%{kinds: ~w(events boxes clubs), max_price_cents: 2000})
      assert up_to.kinds == ~w(events clubs)
      assert up_to.min_price_cents == nil

      # «Δωρεάν» with a range reaches the range down to free.
      with_free = plan(%{cost: ["free"], min_price_cents: 500, max_price_cents: 2000})
      assert with_free.kinds == ~w(events clubs)
      assert {with_free.min_price_cents, with_free.max_price_cents} == {nil, 2000}
    end

    test "a minimum of 0 is no minimum, and the range round-trips" do
      {:ok, filter} = AroundFilter.parse(%{min_price_cents: 0, max_price_cents: 1500}, @vocabulary)
      assert filter.min_price_cents == nil

      {:ok, filter} = AroundFilter.parse(%{min_price_cents: 500}, @vocabulary)
      assert AroundFilter.to_params(filter)["min_price_cents"] == 500
      assert AroundFilter.active_count(filter) == 1
      assert {:ok, ^filter} = AroundFilter.parse(AroundFilter.to_params(filter), @vocabulary)
    end

    test "tags pass through as nil when empty, windows only when asked" do
      assert %{disciplines: nil, audiences: nil, windows: nil} = plan(%{})

      assert %{disciplines: ["hyrox"], windows: [_ | _]} =
               plan(%{disciplines: ["hyrox"], when: "today"})
    end

    test "people with a gym see other boxes collapsed, never on the map or in alerts, and never their own" do
      assert %{boxes_placement: "category", exclude_ids: []} = plan(%{})

      list = plan(%{}, @member)
      assert list.boxes_placement == "collapsed"
      assert "boxes" in list.kinds
      assert list.exclude_ids == @member.organization_ids

      refute "boxes" in plan(%{}, @member, :pins).kinds
      refute "boxes" in plan(%{}, @member, :alert).kinds
      assert "boxes" in plan(%{}, @visitor, :alert).kinds
    end

    test "posts look back 60 days and alerts count only what is new" do
      assert plan(%{}).since == DateTime.add(@now, -60 * 86_400, :second)
      since = ~U[2026-10-20 07:00:00Z]
      assert %{created_after: ^since} = AroundPlan.created_after(plan(%{}), since)
    end

    test "limits are clamped" do
      assert AroundPlan.section_limit(nil) == 5
      assert AroundPlan.section_limit(99) == 10
      assert AroundPlan.page_limit(0) == 1
      assert AroundPlan.page_limit("x") == 20
    end
  end

  defp uuid(n), do: "00000000-0000-0000-0000-#{String.pad_leading(Integer.to_string(n), 12, "0")}"
end
