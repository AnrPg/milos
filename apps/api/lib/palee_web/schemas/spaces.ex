defmodule PaleeWeb.Schemas.Spaces do
  @moduledoc "OpenAPI schemas for spaces, floor plans and the cleaning schedule (ADR-202)."

  alias OpenApiSpex.Schema

  @uuid %Schema{type: :string, format: :uuid}
  @nullable_uuid %Schema{type: :string, format: :uuid, nullable: true}
  @time %Schema{type: :string, format: :"date-time"}
  @nullable_time %Schema{type: :string, format: :"date-time", nullable: true}

  def area do
    %Schema{
      title: "SpaceArea",
      type: :object,
      nullable: true,
      description:
        "A polygon on the floor plan in normalized coordinates (0..1, origin top-left).",
      properties: %{
        points: %Schema{
          type: :array,
          minItems: 3,
          maxItems: 32,
          items: %Schema{
            type: :array,
            minItems: 2,
            maxItems: 2,
            items: %Schema{type: :number, minimum: 0, maximum: 1}
          }
        }
      },
      required: [:points]
    }
  end

  def unavailability do
    %Schema{
      title: "SpaceUnavailability",
      type: :object,
      properties: %{
        id: @uuid,
        space_id: @uuid,
        starts_at: @time,
        ends_at: @time,
        reason: %Schema{type: :string, nullable: true},
        created_by_id: @nullable_uuid
      },
      required: [:id, :space_id, :starts_at, :ends_at]
    }
  end

  def space do
    %Schema{
      title: "Space",
      type: :object,
      properties: %{
        id: @uuid,
        name: %Schema{type: :string},
        description: %Schema{type: :string, nullable: true},
        directions: %Schema{type: :string, nullable: true},
        location_id: @nullable_uuid,
        tasks: %Schema{type: :array, items: %Schema{type: :string}},
        floor_plan_id: @nullable_uuid,
        area: area(),
        archived_at: @nullable_time,
        unavailability: %Schema{type: :array, items: unavailability()}
      },
      required: [:id, :name, :tasks]
    }
  end

  def space_class do
    %Schema{
      title: "SpaceClass",
      type: :object,
      properties: %{
        id: @uuid,
        name: %Schema{type: :string},
        scheduled_at: @time,
        duration_minutes: %Schema{type: :integer},
        coach_user_id: @nullable_uuid,
        capacity: %Schema{type: :integer},
        approved_booking_count: %Schema{type: :integer}
      },
      required: [:id, :name, :scheduled_at, :duration_minutes]
    }
  end

  def equipment do
    %Schema{
      title: "SpaceEquipment",
      type: :object,
      properties: %{
        machine_id: @uuid,
        name: %Schema{type: :string},
        status: %Schema{type: :string},
        quantity: %Schema{type: :integer}
      },
      required: [:machine_id, :name, :status, :quantity]
    }
  end

  def space_detail do
    %Schema{
      title: "SpaceDetail",
      type: :object,
      properties:
        Map.merge(space().properties, %{
          classes: %Schema{type: :array, items: space_class()},
          equipment: %Schema{type: :array, items: equipment()},
          photos: %Schema{type: :array, items: photo()},
          points: %Schema{type: :array, items: cleaning_point()}
        }),
      required: [:id, :name, :tasks, :unavailability, :classes, :equipment, :photos, :points]
    }
  end

  def floor_plan do
    %Schema{
      title: "FloorPlan",
      type: :object,
      properties: %{
        id: @uuid,
        location_id: @nullable_uuid,
        name: %Schema{type: :string},
        media_id: @uuid,
        sort_order: %Schema{type: :integer},
        shown_in_classes: %Schema{
          type: :boolean,
          description:
            "ADR-290: this floor shows in the class view when the gym shows its floor plans."
        },
        image_url: %Schema{type: :string, nullable: true},
        width: %Schema{type: :integer, nullable: true},
        height: %Schema{type: :integer, nullable: true}
      },
      required: [:id, :name, :media_id, :sort_order]
    }
  end

  def space_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        name: %Schema{type: :string, minLength: 1, maxLength: 80},
        description: %Schema{type: :string, maxLength: 2000, nullable: true},
        directions: %Schema{type: :string, maxLength: 2000, nullable: true},
        location_id: @nullable_uuid,
        tasks: %Schema{type: :array, maxItems: 30, items: %Schema{type: :string, maxLength: 120}},
        floor_plan_id: @nullable_uuid,
        area: area()
      }
    }
  end

  def unavailability_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        starts_at: @time,
        ends_at: @time,
        reason: %Schema{type: :string, maxLength: 500, nullable: true}
      },
      required: [:starts_at, :ends_at]
    }
  end

  def floor_plan_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        location_id: @nullable_uuid,
        name: %Schema{type: :string, minLength: 1, maxLength: 80},
        media_id: @uuid,
        sort_order: %Schema{type: :integer, minimum: 0, maximum: 999},
        shown_in_classes: %Schema{type: :boolean}
      }
    }
  end

  def schedule do
    %Schema{
      title: "CleaningSchedule",
      type: :object,
      properties: %{
        id: @uuid,
        space_id: @uuid,
        weekdays: %Schema{type: :array, items: %Schema{type: :integer, minimum: 1, maximum: 7}},
        times: %Schema{type: :array, items: %Schema{type: :string, format: :time}},
        comment: %Schema{type: :string, nullable: true}
      },
      required: [:id, :space_id, :weekdays, :times]
    }
  end

  def schedule_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        weekdays: %Schema{
          type: :array,
          minItems: 1,
          maxItems: 7,
          items: %Schema{type: :integer, minimum: 1, maximum: 7}
        },
        times: %Schema{
          type: :array,
          maxItems: 12,
          items: %Schema{type: :string, pattern: ~r/^\d{2}:\d{2}(:\d{2})?$/}
        },
        comment: %Schema{type: :string, maxLength: 500, nullable: true}
      },
      required: [:weekdays]
    }
  end

  def due do
    %Schema{
      title: "CleaningDue",
      type: :object,
      properties: %{
        space_id: @uuid,
        name: %Schema{type: :string},
        location_id: @nullable_uuid,
        tasks: %Schema{type: :array, items: %Schema{type: :string}},
        floor_plan_id: @nullable_uuid,
        area: area(),
        times: %Schema{type: :array, items: %Schema{type: :string, format: :time}},
        comment: %Schema{type: :string, nullable: true},
        cleanings_due: %Schema{type: :integer},
        cleanings_done: %Schema{type: :integer},
        done: %Schema{type: :boolean},
        points: %Schema{type: :array, items: cleaning_point()}
      },
      required: [
        :space_id,
        :name,
        :tasks,
        :times,
        :cleanings_due,
        :cleanings_done,
        :done
      ]
    }
  end

  def placement do
    %Schema{
      title: "MachinePlacement",
      type: :object,
      properties: %{
        space_id: @uuid,
        quantity: %Schema{type: :integer, minimum: 1},
        positions: %Schema{
          type: :array,
          maxItems: 500,
          description:
            "ADR-290: a pin per item on the space's floor plan, `[x, y]` normalized (0..1).",
          items: %Schema{
            type: :array,
            minItems: 2,
            maxItems: 2,
            items: %Schema{type: :number, minimum: 0, maximum: 1}
          }
        }
      },
      required: [:space_id, :quantity]
    }
  end

  # ── ADR-290 ─────────────────────────────────────────────────────────────

  def settings do
    %Schema{
      title: "SpaceSettings",
      type: :object,
      properties: %{
        floor_plans_in_classes: %Schema{
          type: :boolean,
          description:
            "Members and athletes open the floor plan with the class's room coloured, and the room's photos."
        }
      },
      required: [:floor_plans_in_classes]
    }
  end

  def settings_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{floor_plans_in_classes: %Schema{type: :boolean}},
      required: [:floor_plans_in_classes]
    }
  end

  @image %{
    url: %Schema{type: :string, nullable: true},
    width: %Schema{type: :integer, nullable: true},
    height: %Schema{type: :integer, nullable: true}
  }

  def photo do
    %Schema{
      title: "SpacePhoto",
      type: :object,
      properties:
        Map.merge(@image, %{
          id: @uuid,
          space_id: @uuid,
          media_id: @uuid,
          caption: %Schema{type: :string, nullable: true},
          public: %Schema{type: :boolean, description: "Shown on the public box page."},
          sort_order: %Schema{type: :integer}
        }),
      required: [:id, :space_id, :media_id, :public, :sort_order]
    }
  end

  def cleaning_point do
    %Schema{
      title: "CleaningPoint",
      type: :object,
      properties:
        Map.merge(@image, %{
          id: @uuid,
          space_id: @uuid,
          media_id: @uuid,
          instruction: %Schema{type: :string},
          sort_order: %Schema{type: :integer}
        }),
      required: [:id, :space_id, :media_id, :instruction, :sort_order]
    }
  end

  def photo_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        media_id: @uuid,
        caption: %Schema{type: :string, maxLength: 200, nullable: true},
        public: %Schema{type: :boolean}
      }
    }
  end

  def cleaning_point_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        media_id: @uuid,
        instruction: %Schema{type: :string, minLength: 1, maxLength: 500}
      }
    }
  end

  def order_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{ids: %Schema{type: :array, maxItems: 100, items: @uuid}},
      required: [:ids]
    }
  end

  def class_room do
    %Schema{
      title: "ClassRoom",
      type: :object,
      properties: %{
        space: %Schema{
          type: :object,
          properties: %{
            id: @uuid,
            name: %Schema{type: :string},
            description: %Schema{type: :string, nullable: true},
            directions: %Schema{type: :string, nullable: true}
          },
          required: [:id, :name]
        },
        floor_plan: Map.put(floor_plan(), :nullable, true),
        area: area(),
        photos: %Schema{type: :array, items: photo()}
      },
      required: [:space, :floor_plan, :photos]
    }
  end
end
