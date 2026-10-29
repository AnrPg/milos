defmodule PaleeWeb.Schemas.BoxScreens do
  @moduledoc "OpenAPI schemas of box screens (ADR-253)."

  alias OpenApiSpex.{MediaType, RequestBody, Schema}
  alias PaleeWeb.Schemas.Workout

  @uuid %Schema{type: :string, format: :uuid}
  @nullable_uuid %Schema{type: :string, format: :uuid, nullable: true}
  @time %Schema{type: :string, format: :"date-time"}
  @nullable_time %Schema{type: :string, format: :"date-time", nullable: true}
  @nullable_text %Schema{type: :string, nullable: true}
  @override_views ["wod", "timer", "leaderboard", "bookings", "class"]

  def uuid, do: @uuid

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  def error do
    %Schema{
      type: :object,
      properties: %{code: %Schema{type: :string}, error: %Schema{type: :string}},
      required: [:code, :error]
    }
  end

  # ── Staff ───────────────────────────────────────────────────────────────

  def override do
    %Schema{
      title: "BoxScreenOverride",
      type: :object,
      nullable: true,
      description: "What staff pinned on the screen; null when it follows the day automatically",
      properties: %{
        view: %Schema{type: :string, enum: @override_views},
        slot_id: @nullable_uuid,
        until: @nullable_time
      },
      required: [:slot_id, :until, :view]
    }
  end

  def screen do
    %Schema{
      title: "BoxScreen",
      type: :object,
      properties: %{
        id: @uuid,
        name: %Schema{type: :string},
        location_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "The branch; null for the whole box"
        },
        paired: %Schema{type: :boolean},
        paired_at: @nullable_time,
        last_seen_at: @nullable_time,
        pairing_expires_at: %Schema{
          type: :string,
          format: :"date-time",
          nullable: true,
          description: "When the pending pairing code stops working; null without one"
        },
        override: override(),
        focus_changed: %Schema{
          type: :object,
          nullable: true,
          description: "Who last changed what the screen shows, and when",
          properties: %{
            at: @time,
            by: %Schema{
              type: :object,
              nullable: true,
              properties: %{id: @uuid, name: @nullable_text},
              required: [:id, :name]
            }
          },
          required: [:at, :by]
        },
        inserted_at: @time
      },
      required: [
        :focus_changed,
        :id,
        :inserted_at,
        :last_seen_at,
        :location_id,
        :name,
        :override,
        :paired,
        :paired_at,
        :pairing_expires_at
      ]
    }
  end

  def pairing_code do
    %Schema{
      title: "BoxScreenPairingCode",
      type: :object,
      description: "Shown once: typed on the TV within 15 minutes",
      properties: %{
        code: %Schema{type: :string, pattern: "^[A-Z0-9]{4}-[A-Z0-9]{4}$", example: "ACEF-3467"},
        expires_at: @time
      },
      required: [:code, :expires_at]
    }
  end

  def screen_list do
    %Schema{
      type: :object,
      properties: %{
        screens: %Schema{type: :array, items: screen()},
        max_screens: %Schema{type: :integer},
        override_views: %Schema{
          type: :array,
          items: %Schema{type: :string, enum: @override_views}
        }
      },
      required: [:max_screens, :override_views, :screens]
    }
  end

  def screen_response do
    %Schema{type: :object, properties: %{screen: screen()}, required: [:screen]}
  end

  def screen_with_code do
    %Schema{
      type: :object,
      properties: %{screen: screen(), pairing_code: pairing_code()},
      required: [:pairing_code, :screen]
    }
  end

  def create_request do
    %Schema{
      type: :object,
      properties: %{
        name: %Schema{type: :string, minLength: 1, maxLength: 60},
        location_id: @nullable_uuid
      },
      required: [:name]
    }
  end

  def update_request do
    %Schema{
      type: :object,
      properties: %{
        name: %Schema{type: :string, minLength: 1, maxLength: 60},
        location_id: @nullable_uuid
      }
    }
  end

  def override_request do
    %Schema{
      type: :object,
      properties: %{
        view: %Schema{type: :string, enum: @override_views},
        slot_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "One of today's classes on the screen; required for `class`"
        },
        until: %Schema{
          type: :string,
          format: :"date-time",
          nullable: true,
          description: "When the screen goes back to automatic (within 24 hours); null to keep it"
        }
      },
      required: [:view]
    }
  end

  # ── One class, from its timer remote ────────────────────────────────────

  def class_screen_list do
    %Schema{
      title: "ClassScreenList",
      type: :object,
      description:
        "The box screens the person may change for this class: its coach (today, screens " <>
          "of the class's branch or the whole box) or staff who manage screens",
      properties: %{
        screens: %Schema{type: :array, items: screen()},
        views: %Schema{
          type: :array,
          description: "What the person may pin: a coach `timer`, `leaderboard` and `wod`",
          items: %Schema{type: :string, enum: @override_views}
        }
      },
      required: [:screens, :views]
    }
  end

  def class_override_request do
    %Schema{
      type: :object,
      properties: %{
        view: %Schema{type: :string, enum: @override_views},
        until: %Schema{
          type: :string,
          format: :"date-time",
          nullable: true,
          description: "When the screen goes back to automatic (within 24 hours); null to keep it"
        }
      },
      required: [:view]
    }
  end

  # ── TV ──────────────────────────────────────────────────────────────────

  def pair_request do
    %Schema{
      type: :object,
      properties: %{code: %Schema{type: :string, minLength: 8, maxLength: 20}},
      required: [:code]
    }
  end

  def token_response do
    %Schema{
      title: "BoxScreenToken",
      type: :object,
      properties: %{token: %Schema{type: :string}, expires_at: @time},
      required: [:expires_at, :token]
    }
  end

  def pair_response do
    %Schema{
      type: :object,
      properties: %{
        token: %Schema{type: :string},
        expires_at: @time,
        screen: %Schema{
          type: :object,
          properties: %{id: @uuid, name: %Schema{type: :string}},
          required: [:id, :name]
        },
        box: %Schema{
          type: :object,
          description: "The box; `id` is the topic of `box_screen:<id>` on `/box_screen_socket`",
          properties: %{id: @uuid, name: %Schema{type: :string}},
          required: [:id, :name]
        }
      },
      required: [:box, :expires_at, :screen, :token]
    }
  end

  defp bookings do
    %Schema{
      type: :object,
      description:
        "First names of booked members who do not hide; hidden people, guests and trials only counted",
      properties: %{
        count: %Schema{type: :integer},
        capacity: %Schema{type: :integer},
        waitlist: %Schema{type: :integer},
        names: %Schema{type: :array, items: %Schema{type: :string}},
        unnamed: %Schema{type: :integer}
      },
      required: [:capacity, :count, :names, :unnamed, :waitlist]
    }
  end

  defp class do
    %Schema{
      title: "BoxScreenClass",
      type: :object,
      properties: %{
        id: @uuid,
        name: @nullable_text,
        class_type: @nullable_text,
        scheduled_at: @time,
        ends_at: @time,
        duration_minutes: %Schema{type: :integer},
        location_id: @nullable_uuid,
        cancelled: %Schema{type: :boolean},
        coach_name: @nullable_text,
        workout_id: @nullable_uuid,
        bookings: bookings()
      },
      required: [
        :bookings,
        :cancelled,
        :class_type,
        :coach_name,
        :duration_minutes,
        :ends_at,
        :id,
        :location_id,
        :name,
        :scheduled_at,
        :workout_id
      ]
    }
  end

  defp workout do
    %Schema{
      title: "BoxScreenWorkout",
      type: :object,
      properties: %{
        id: @uuid,
        title: @nullable_text,
        type: @nullable_text,
        body: Workout.body_schema()
      },
      required: [:body, :id, :title, :type]
    }
  end

  defp leaderboard do
    %Schema{
      title: "BoxScreenLeaderboard",
      type: :object,
      description: "Only people who opted in to leaderboards; never journal-private results",
      properties: %{
        workout_id: @uuid,
        score: %Schema{
          type: :object,
          nullable: true,
          properties: %{
            name: @nullable_text,
            score_type: @nullable_text,
            unit: @nullable_text
          }
        },
        entries: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              rank: %Schema{type: :integer},
              name: %Schema{type: :string, description: "First word of the display name"},
              value: @nullable_text,
              unit: @nullable_text,
              scale_level_slug: @nullable_text
            },
            required: [:name, :rank, :scale_level_slug, :unit, :value]
          }
        }
      },
      required: [:entries, :score, :workout_id]
    }
  end

  def focus do
    %Schema{
      title: "BoxScreenFocus",
      type: :object,
      description:
        "What the screen puts first: automatically (preview, timer, results, idle) or as staff pinned it",
      properties: %{
        source: %Schema{type: :string, enum: ["auto", "staff"]},
        view: %Schema{
          type: :string,
          enum: ["preview", "timer", "results", "idle" | @override_views]
        },
        slot_id: @nullable_uuid,
        until: @nullable_time
      },
      required: [:slot_id, :source, :until, :view]
    }
  end

  def today do
    %Schema{
      title: "BoxScreenToday",
      type: :object,
      properties: %{
        box: %Schema{
          type: :object,
          description: "The box; `id` is the topic of `box_screen:<id>` on `/box_screen_socket`",
          properties: %{id: @uuid, name: @nullable_text},
          required: [:id, :name]
        },
        screen: %Schema{
          type: :object,
          properties: %{
            id: @uuid,
            name: %Schema{type: :string},
            branch: %Schema{
              type: :object,
              nullable: true,
              properties: %{id: @uuid, name: %Schema{type: :string}},
              required: [:id, :name]
            }
          },
          required: [:branch, :id, :name]
        },
        date: %Schema{type: :string, format: :date, description: "Today on the box's clock"},
        time_zone: %Schema{type: :string},
        server_now: @time,
        classes: %Schema{type: :array, items: class()},
        workouts: %Schema{type: :array, items: workout()},
        leaderboards: %Schema{type: :array, items: leaderboard()},
        focus: focus()
      },
      required: [
        :box,
        :classes,
        :date,
        :focus,
        :leaderboards,
        :screen,
        :server_now,
        :time_zone,
        :workouts
      ]
    }
  end
end
