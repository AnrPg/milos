defmodule MilosTraining.Journal.CrossProviderDomainTest do
  @moduledoc """
  ADR-162 domain rules: the «Οι coach μου» audience policy (an exhaustive
  matrix over kinds, home providers, rungs, membership states, overrides and
  exclusions), the former-provider cutoff, entry sources, the Ροή filter,
  workout identity and the Vault / Πρόοδος filters, providers and the
  merged today card, and the export files.
  """

  use ExUnit.Case, async: true

  alias MilosTraining.Analytics.Domain.ProgressFilter
  alias MilosTraining.Execution.Domain.{VaultFilter, WorkoutIdentity}
  alias MilosTraining.Journal.Domain.{CoachAudience, EntrySource, ExportFormat, JournalFilter}
  alias MilosTraining.Organizations.Domain.{Provider, ProviderToday}

  @a "aaaaaaaa-0000-0000-0000-000000000001"
  @b "bbbbbbbb-0000-0000-0000-000000000002"
  @c "cccccccc-0000-0000-0000-000000000003"
  @rungs ~w(private coach_can_view coach_reply_requested posted)
  @reaching ~w(coach_can_view coach_reply_requested posted)

  defp entry(kind, home, rung), do: %{kind: kind, organization_id: home, journal_visibility: rung}

  describe "CoachAudience matrix" do
    # Members: active at A and B; at A only (B former); B excluded by default.
    @members %{
      both: CoachAudience.member([@a, @b]),
      a_only: CoachAudience.member([@a]),
      b_excluded: CoachAudience.member([@a, @b], [@b])
    }
    @overrides [nil, [@b], [@a], [@a, @b]]

    test "nothing below a coach rung reaches anyone, whatever the audience" do
      for kind <- CoachAudience.shareable_kinds() ++ ~w(craving wellness),
          home <- [nil, @a, @b],
          {_name, member} <- @members,
          override <- @overrides do
        assert CoachAudience.readers(entry(kind, home, "private"), member, override) ==
                 MapSet.new()
      end
    end

    test "a provider the member is not an active member of never reads (former cutoff)" do
      for kind <- CoachAudience.shareable_kinds() ++ ~w(injury review craving),
          home <- [nil, @a, @b, @c],
          rung <- @rungs ++ ["rated"],
          override <- @overrides ++ [[@c]] do
        readers = CoachAudience.readers(entry(kind, home, rung), @members.a_only, override)
        refute MapSet.member?(readers, @b), "#{kind} #{inspect(home)} #{rung}"
        refute MapSet.member?(readers, @c)
      end
    end

    test "the home provider always reads on a coach rung while active" do
      for kind <- CoachAudience.shareable_kinds() ++ ~w(craving),
          rung <- @reaching,
          {_name, member} <- @members,
          override <- @overrides do
        assert CoachAudience.visible_to?(entry(kind, @a, rung), @a, member, override)
      end
    end

    test "an entry recorded at A reaches B only when shared with B (Q5)" do
      for kind <- CoachAudience.shareable_kinds(), rung <- @reaching do
        e = entry(kind, @a, rung)
        refute CoachAudience.visible_to?(e, @b, @members.both, nil)
        refute CoachAudience.visible_to?(e, @b, @members.both, [@a])
        assert CoachAudience.visible_to?(e, @b, @members.both, [@b])
        # The default exclusion does not undo an explicit share.
        assert CoachAudience.visible_to?(e, @b, @members.b_excluded, [@b])
      end
    end

    test "a provider-less entry goes to the default audience unless it has its own" do
      for kind <- CoachAudience.shareable_kinds(), rung <- @reaching do
        e = entry(kind, nil, rung)
        assert CoachAudience.readers(e, @members.both, nil) == MapSet.new([@a, @b])
        assert CoachAudience.readers(e, @members.b_excluded, nil) == MapSet.new([@a])
        assert CoachAudience.readers(e, @members.both, [@b]) == MapSet.new([@b])
        assert CoachAudience.readers(e, @members.a_only, [@a, @b]) == MapSet.new([@a])
      end
    end

    test "kinds that are not shareable stay with their home provider" do
      for kind <- ~w(craving wellness body), rung <- @reaching, override <- @overrides do
        assert CoachAudience.readers(entry(kind, nil, rung), @members.both, override) ==
                 MapSet.new()

        assert CoachAudience.readers(entry(kind, @a, rung), @members.both, override) ==
                 MapSet.new([@a])
      end
    end

    test "injuries and reviews reach the home provider on any rung" do
      for kind <- ~w(injury review), rung <- @rungs ++ ["rated"] do
        assert CoachAudience.readers(entry(kind, @a, rung), @members.both, [@b]) ==
                 MapSet.new([@a])

        assert CoachAudience.readers(entry(kind, @b, rung), @members.a_only, nil) ==
                 MapSet.new()
      end
    end

    test "reach decides which rungs a member may pick" do
      assert CoachAudience.reach(entry("note", @a, "private"), @members.both) == :gym
      assert CoachAudience.reach(entry("note", nil, "private"), @members.both) == :audience
      assert CoachAudience.reach(entry("note", nil, "private"), CoachAudience.member([])) == :none

      assert CoachAudience.reach(entry("note", nil, "private"), CoachAudience.member([@a], [@a])) ==
               :none

      assert CoachAudience.reach(entry("craving", nil, "private"), @members.both) == :none
    end

    test "own audiences are validated against the active providers" do
      e = entry("note", @a, "private")
      assert CoachAudience.validate_override(nil, e, @members.both) == {:ok, nil}
      assert CoachAudience.validate_override([@b, @a, @b], e, @members.both) == {:ok, [@b]}
      assert CoachAudience.validate_override([@a], e, @members.both) == {:ok, nil}

      assert CoachAudience.validate_override([@c], e, @members.both) ==
               {:error, :unknown_provider}

      assert CoachAudience.validate_override([@b], e, @members.a_only) ==
               {:error, :unknown_provider}

      assert CoachAudience.validate_override([], entry("note", nil, "private"), @members.both) ==
               {:error, :empty_audience}

      assert CoachAudience.validate_override([@a], entry("craving", nil, "x"), @members.both) ==
               {:error, :audience_not_supported}

      assert CoachAudience.validate_override("x", e, @members.both) == {:error, :unknown_provider}
    end

    test "a default audience is stored as the providers left out" do
      assert CoachAudience.exclusions_for([@a], @members.both) == {:ok, [@b]}
      assert CoachAudience.exclusions_for([@a, @b], @members.both) == {:ok, []}
      assert CoachAudience.exclusions_for([@c], @members.both) == {:error, :unknown_provider}
    end
  end

  describe "EntrySource" do
    @directory %{@a => %{name: "Box", former: false}, @b => %{name: "Nikos", former: true}}

    test "labels providers, former providers, devices and freeform entries" do
      assert EntrySource.label(@a, nil, @directory) ==
               %{kind: "organization", organization_id: @a, name: "Box", former: false}

      assert %{former: true, name: "Nikos"} = EntrySource.label(@b, nil, @directory)
      assert %{former: true, name: nil} = EntrySource.label(@c, nil, @directory)
      assert %{kind: "device", name: "Garmin"} = EntrySource.label(nil, "garmin", @directory)
      assert %{kind: "device"} = EntrySource.label(@a, "garmin", @directory)
      assert %{kind: "freeform"} = EntrySource.label(nil, "manual", @directory)
      assert EntrySource.token(EntrySource.label(@a, nil, @directory)) == @a
      assert EntrySource.matches?(EntrySource.label(nil, nil, @directory), ["freeform"])
      refute EntrySource.matches?(EntrySource.label(nil, nil, @directory), [@a])
    end
  end

  describe "JournalFilter" do
    test "parses lists or comma strings into the canonical, versioned form" do
      assert {:ok, filter} =
               JournalFilter.parse(%{
                 "v" => 1,
                 "kinds" => "note,pr",
                 "sources" => [String.upcase(@a), "freeform"],
                 "visibilities" => ["private"],
                 "date_from" => "2026-10-01",
                 "date_to" => "2026-10-02",
                 "q" => "  back   squat "
               })

      assert filter.kinds == ~w(pr note)
      assert filter.sources == [@a, "freeform"]
      assert filter.q == "back squat"
      assert JournalFilter.active_count(filter) == 5

      assert %{"v" => 1, "kinds" => ~w(pr note), "date_from" => "2026-10-01"} =
               JournalFilter.to_params(filter)

      assert {:ok, ^filter} = filter |> JournalFilter.to_params() |> JournalFilter.parse()
      assert JournalFilter.default?(JournalFilter.default())
    end

    test "refuses what it cannot honour" do
      assert {:error, [v: _]} = JournalFilter.parse(%{"v" => 2})
      assert {:error, [kinds: _]} = JournalFilter.parse(%{"kinds" => ["post"]})
      assert {:error, [sources: _]} = JournalFilter.parse(%{"sources" => ["gym"]})
      assert {:error, [visibilities: _]} = JournalFilter.parse(%{"visibilities" => ["all"]})

      assert {:error, [date_to: _]} =
               JournalFilter.parse(%{"date_from" => "2026-10-02", "date_to" => "2026-10-01"})

      assert {:error, [date_from: _]} = JournalFilter.parse(%{"date_from" => "yesterday"})
      assert {:error, [q: _]} = JournalFilter.parse(%{"q" => "a"})
      assert {:error, [q: _]} = JournalFilter.parse(%{"q" => String.duplicate("a", 101)})
      assert {:error, [filter: _]} = JournalFilter.parse("x")
      assert {:ok, %{q: nil}} = JournalFilter.parse(%{"q" => "   ", "unknown" => 1})
    end

    test "narrows kinds and builds the SQL query" do
      {:ok, filter} = JournalFilter.parse(%{"q" => "50% off_", "sources" => ["device", @a]})
      assert JournalFilter.kinds(filter, ~w(body note wellness pr)) == ~w(note pr)

      assert %{
               sources?: true,
               organization_ids: [@a],
               device?: true,
               freeform?: false,
               q: "%50\\% off\\_%"
             } = JournalFilter.to_query(filter)

      {:ok, dated} =
        JournalFilter.parse(%{"date_from" => "2026-10-01", "date_to" => "2026-10-01"})

      query = JournalFilter.to_query(dated)
      assert query.from == ~U[2026-10-01 00:00:00Z]
      assert query.to == ~U[2026-10-02 00:00:00Z]
      assert {query.from_date, query.to_date} == {~D[2026-10-01], ~D[2026-10-02]}
      assert JournalFilter.active_count(dated) == 1

      # The member's own day: Athens is UTC+3 in summer time.
      athens = JournalFilter.to_query(dated, "Europe/Athens")
      assert athens.from == ~U[2026-09-30 21:00:00Z]
      assert athens.to == ~U[2026-10-01 21:00:00Z]
      assert {athens.from_date, athens.to_date} == {~D[2026-10-01], ~D[2026-10-02]}

      # A day that starts in a DST gap starts when the clocks resume.
      {:ok, gap} = JournalFilter.parse(%{"date_from" => "2026-09-06"})
      assert JournalFilter.to_query(gap, "America/Santiago").from == ~U[2026-09-06 04:00:00Z]

      assert JournalFilter.valid_time_zone?("Europe/Athens")
      refute JournalFilter.valid_time_zone?("Mars/Olympus")
    end
  end

  describe "WorkoutIdentity" do
    test "the same benchmark is one identity across providers" do
      assert WorkoutIdentity.key(%{title: "Fran", type: :crossfit}) == "benchmark:fran"
      assert WorkoutIdentity.key(%{title: " FRAN! ", type: "strength"}) == "benchmark:fran"
      assert WorkoutIdentity.key(%{title: "Filthy Fifty"}) == "benchmark:filthy_fifty"

      assert WorkoutIdentity.key(%{title: "Box WOD", tags: ["benchmark:Open 24.1"]}) ==
               "benchmark:open_24_1"

      assert WorkoutIdentity.key(%{title: "Lower body A", source_workout_id: @a}) ==
               "library:" <> @a

      assert WorkoutIdentity.key(%{title: "Lower Body  A", type: :strength}) ==
               "title:lower body a:strength"

      assert WorkoutIdentity.key(%{title: "Πόδια Ά"}) == "title:ποδια α"
      assert WorkoutIdentity.key(%{title: nil}) == nil
      assert WorkoutIdentity.key_benchmark("benchmark:dt") == "dt"
      assert WorkoutIdentity.key_benchmark("title:x") == nil
      assert WorkoutIdentity.benchmark_name("filthy_fifty") == "Filthy Fifty"
      assert WorkoutIdentity.benchmark_name("dt") == "DT"
    end
  end

  describe "VaultFilter and ProgressFilter" do
    @attempt %{
      key: "benchmark:fran",
      type: "crossfit",
      exercise_names: ["Thruster", "Pull-up"],
      source_token: @a,
      on: ~D[2026-10-05]
    }

    test "the Vault filter matches attempts" do
      {:ok, all} = VaultFilter.parse(%{})
      assert VaultFilter.match?(all, @attempt)

      {:ok, filter} =
        VaultFilter.parse(%{
          "disciplines" => "crossfit",
          "benchmark" => "Fran",
          "exercise" => "thrus",
          "sources" => [@a],
          "date_from" => "2026-10-01",
          "date_to" => "2026-10-05"
        })

      assert VaultFilter.match?(filter, @attempt)
      assert VaultFilter.active_count(filter) == 5
      refute VaultFilter.match?(filter, %{@attempt | key: "benchmark:grace"})
      refute VaultFilter.match?(filter, %{@attempt | type: "strength"})
      refute VaultFilter.match?(filter, %{@attempt | source_token: "freeform"})
      refute VaultFilter.match?(filter, %{@attempt | on: ~D[2026-10-06]})
      refute VaultFilter.match?(filter, %{@attempt | exercise_names: ["Squat"]})
      assert {:ok, ^filter} = filter |> VaultFilter.to_params() |> VaultFilter.parse()
      assert {:error, [disciplines: _]} = VaultFilter.parse(%{"disciplines" => ["yoga"]})
    end

    test "the Πρόοδος filter defaults to everything" do
      {:ok, filter} = ProgressFilter.parse(nil)
      assert filter.range == "all"
      assert ProgressFilter.active_count(filter) == 0
      assert ProgressFilter.since(filter, ~D[2026-10-21]) == nil

      {:ok, filter} =
        ProgressFilter.parse(%{"range" => "6m", "sources" => "freeform", "exercise" => "squat"})

      assert ProgressFilter.since(filter, ~D[2026-10-21]) == ~D[2026-04-21]
      assert ProgressFilter.active_count(filter) == 3
      assert {:ok, ^filter} = filter |> ProgressFilter.to_params() |> ProgressFilter.parse()
      assert {:error, [range: _]} = ProgressFilter.parse(%{"range" => "2w"})
    end
  end

  describe "Provider and ProviderToday" do
    defp row(id, name, status, opts \\ []) do
      %{
        organization_id: id,
        name: name,
        slug: String.downcase(name),
        provider_kind: Keyword.get(opts, :kind, "gym"),
        logo_url: nil,
        primary_color: nil,
        membership_status: status,
        roles: ["member"],
        joined_at: ~N[2026-01-01 00:00:00],
        ended_at: Keyword.get(opts, :ended_at),
        organization_status: Keyword.get(opts, :org_status, "active")
      }
    end

    test "former providers are those whose membership ended or that closed" do
      providers =
        Enum.map(
          [
            row(@a, "Zeta box", "active"),
            row(@b, "Nikos", "active", kind: "coach"),
            row(@c, "Old box", "revoked", ended_at: ~N[2026-10-01 00:00:00]),
            row("dddddddd-0000-0000-0000-000000000004", "Closed", "active",
              org_status: "suspended"
            )
          ],
          &Provider.from_row/1
        )

      {active, former} = Provider.split(providers)
      assert Enum.map(active, & &1.name) == ["Nikos", "Zeta box"]
      assert Enum.map(former, & &1.name) == ["Old box", "Closed"]
      assert hd(active).kind == "coach"
      assert Provider.active_ids(providers) == [@a, @b]
      assert Provider.directory(providers)[@c] == %{name: "Old box", former: true}
      assert Provider.selected(active, @a) == @a
      assert Provider.selected(active, @c) == @b
      assert Provider.selected([], @a) == nil
    end

    test "today merges in time order, untimed first, and marks failures partial" do
      at = fn hour -> DateTime.new!(~D[2026-10-21], Time.new!(hour, 0, 0), "Etc/UTC") end

      merged =
        ProviderToday.merge([
          {@a, {:ok, [%{kind: "class", at: at.(18), title: "Fran"}]}},
          {@b, {:ok, [%{kind: "appointment", at: at.(8)}, %{kind: "program", at: nil}]}},
          {@c, {:error, :boom}}
        ])

      assert Enum.map(merged.items, & &1.kind) == ~w(program appointment class)
      assert merged.partial
      assert merged.failed == [@c]
      refute ProviderToday.merge([{@a, {:ok, []}}]).partial
    end
  end

  describe "ExportFormat" do
    test "JSON keeps every entry and the CSV holds training rows" do
      items = [
        %{
          kind: "execution",
          occurred_at: ~U[2026-10-01 08:00:00Z],
          journal_visibility: "private",
          source: %{kind: "organization", name: "Box, Kypseli", former: true},
          entry: %{
            workout_title: "Fran",
            workout_type: :crossfit,
            total_elapsed_ms: 252_000,
            section_scores: [%{"section_name" => "For time", "value" => 252, "unit" => "s"}],
            nested: %Decimal{sign: 1, coef: 15, exp: -1}
          }
        },
        %{
          kind: "note",
          occurred_at: ~U[2026-10-02 08:00:00Z],
          journal_visibility: "private",
          entry: %{}
        }
      ]

      csv = ExportFormat.training_csv(items)
      [header, row] = String.split(csv, "\r\n", trim: true)
      assert header =~ "date,kind,source,provider"

      assert row =~
               ~s(execution,organization,"Box, Kypseli",true,Fran,crossfit,252,,For time: 252 s,private)

      json = ExportFormat.json(items, [], ~U[2026-10-03 00:00:00Z]) |> Jason.decode!()
      assert json["format"] == "milos.journal.v1"
      assert length(json["entries"]) == 2
      assert hd(json["entries"])["entry"]["nested"] == "1.5"
    end
  end
end
