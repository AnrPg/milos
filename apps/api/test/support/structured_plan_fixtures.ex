defmodule Palee.StructuredPlanFixtures do
  @moduledoc "ADR-270: structured WOD plans for tests, from the coach's own program (the approved mockup's sample)."

  def ex(id, name, dose \\ "", load \\ "", more \\ %{}) do
    Map.merge(
      %{
        "id" => id,
        "kind" => "ex",
        "name" => name,
        "dose" => dose,
        "load" => load,
        "cells" => []
      },
      more
    )
  end

  def rest(id, more),
    do:
      Map.merge(
        %{"id" => id, "kind" => "rest", "name" => "", "dose" => "", "load" => "", "cells" => []},
        more
      )

  def cells(pairs), do: Enum.map(pairs, fn {d, l} -> %{"d" => d, "l" => l} end)

  def section(flow, params, blocks, more \\ %{}) do
    Map.merge(
      %{"v" => 1, "flow" => flow, "params" => params, "blocks" => blocks, "score" => score(flow)},
      more
    )
  end

  # The flow's default score (the first of its list).
  def score("sets"), do: "none"
  def score("for_time"), do: "time"
  def score("amrap"), do: "rounds_reps"
  def score("emom"), do: "none"
  def score("intervals"), do: "total_reps"
  def score("rest"), do: "none"

  def program do
    [
      section("sets", %{"sets" => "4", "rest" => "2:00"}, [
        [
          ex("r1", "Back Squat", "", "", %{
            "note" => "Έλεγχος στο κατέβασμα, με ζώνη",
            "extra" => ["tempo"],
            "cells" =>
              [%{"d" => "12", "l" => "60%", "tempo" => "31X1"}] ++
                cells([{"10", "+5"}, {"8", ""}, {"8", ""}])
          })
        ]
      ]),
      section("sets", %{"sets" => "3-4", "rest" => "90″"}, [
        [
          ex("r2", "Knee Extension", "", "", %{"group" => "g1", "cells" => cells([{"12-15", ""}])}),
          ex("r3", "Standing Calf Raise", "", "", %{
            "group" => "g1",
            "cells" => cells([{"15", ""}])
          }),
          ex("r4", "Cyclist Squat", "", "", %{
            "group" => "g1",
            "note" => "Φτέρνες ψηλά",
            "cells" => cells([{"20", ""}])
          })
        ]
      ]),
      section("sets", %{"sets" => "4", "rest" => "3:00"}, [
        [
          ex("r5", "Ring Dip", "", "", %{"group" => "g2", "cells" => cells([{"7", "με βάρος"}])}),
          rest("r6", %{"group" => "g2", "cells" => [%{"d" => "30″"}]}),
          ex("r7", "Strict HSPU", "", "", %{"group" => "g2", "cells" => cells([{"10", ""}])}),
          rest("r8", %{"group" => "g2", "cells" => [%{"d" => "30″"}]}),
          ex("r9", "Echo Bike", "", "", %{"group" => "g2", "cells" => [%{"d" => "60s max cal"}]})
        ]
      ]),
      section(
        "sets",
        %{"sets" => "5", "rest" => "2:30"},
        [[ex("r10", "Back Squat", "", "", %{"cells" => cells([{"3", "80%"}])})]],
        %{
          "structs" => %{"r10" => %{"kind" => "cluster", "clusters" => "3", "intra" => "15″"}}
        }
      ),
      section("emom", %{"every" => "2:30", "times" => "4"}, [
        [
          ex("r11", "Front Squat", "7", "", %{
            "group" => "g3",
            "note" => "Ίδια κιλά με το top set"
          }),
          ex("r12", "Dual DB Push Press", "8-12", "βαρύ", %{"group" => "g3"})
        ]
      ]),
      section(
        "emom",
        %{"every" => "1:00", "times" => "8"},
        [[ex("r13", "Wall Ball", "20")], [ex("r14", "Burpee to Target", "12")]],
        %{"preset" => "even_odd"}
      ),
      section("amrap", %{"dur" => "7"}, [
        [
          ex("r15", "Butterfly Pull-up", "15"),
          ex("r16", "Power Snatch", "", "", %{
            "perRound" => true,
            "cells" => cells([{"5", "40kg"}, {"10", "+5kg"}, {"15", ""}])
          })
        ]
      ]),
      section(
        "for_time",
        %{"rounds" => "1", "cap" => "", "intEvery" => "2:00"},
        [[ex("r17", "Thruster", "75")]],
        %{
          "mods" => %{"interrupt" => true},
          "interrupt" => [ex("r18", "Burpee over Bar", "10")],
          "preset" => "interrupt"
        }
      ),
      section("for_time", %{"rounds" => "4", "cap" => "20"}, [
        [ex("r19", "Row", "500 m"), ex("r20", "Burpee", "15")],
        [ex("r21", "Run", "400 m"), ex("r22", "Wall Ball", "20")]
      ]),
      section("amrap", %{"dur" => "3-3-3-4", "rest" => "1:00"}, [
        [
          ex("r23", "Echo Bike", "15 cal"),
          ex("r24", "Wall Ball", "25"),
          ex("r25", "Clean & Jerk", "max", "60kg")
        ]
      ]),
      section(
        "intervals",
        %{"work" => "20″", "off" => "", "rounds" => "8", "hrTarget" => "120"},
        [[ex("r26", "Row", "max cal")]],
        %{
          "mods" => %{"hr" => true},
          "levelNotes" => %{"rx" => "Ως τους 120 παλμούς", "scaled" => ""}
        }
      ),
      section("rest", %{"dur" => "2:00"}, []),
      # The web reference program's further cases (validate.test.ts).
      section("amrap", %{"dur" => "12"}, [[ex("r27", "Thruster", "5-10-15…", "22.5kg")]]),
      section("sets", %{"sets" => "4", "rest" => "90-120″"}, [
        [
          ex("r28", "Bulgarian Split Squat", "", "", %{
            "extra" => ["side", "rpe"],
            "cells" => [%{"d" => "4 x 8-10 each side", "l" => "22.5kg", "rpe" => "8"}]
          })
        ]
      ]),
      section("amrap", %{"dur" => "3'-3'-3'-4'", "rest" => "1:00"}, [[ex("r29", "Row", "250 m")]]),
      section("sets", %{"sets" => "4"}, [
        [ex("r30", "Bench Press", "", "", %{"cells" => cells([{"8", "60→80%"}])})]
      ])
    ]
  end
end
