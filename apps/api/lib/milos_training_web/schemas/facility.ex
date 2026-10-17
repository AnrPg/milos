defmodule MilosTrainingWeb.Schemas.Facility do
  @moduledoc "OpenAPI schemas of the Facility context (ADR-097)."

  alias MilosTraining.Facility
  alias OpenApiSpex.Schema

  @uuid %Schema{type: :string, format: :uuid}
  @nullable_uuid %Schema{type: :string, format: :uuid, nullable: true}
  @nullable_string %Schema{type: :string, nullable: true}
  @nullable_number %Schema{type: :number, nullable: true}
  @nullable_date_time %Schema{type: :string, format: :"date-time", nullable: true}

  def location_schema do
    %Schema{
      title: "FacilityLocation",
      type: :object,
      properties: %{
        id: @uuid,
        organization_id: @uuid,
        name: %Schema{type: :string},
        address: @nullable_string,
        latitude: @nullable_number,
        longitude: @nullable_number,
        neighbourhood: @nullable_string,
        city: @nullable_string,
        country_code: @nullable_string,
        opening_hours: %Schema{type: :array, items: opening_hours_span_schema()},
        accessibility: %Schema{type: :array, items: accessibility_schema()},
        archived_at: @nullable_date_time,
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [
        :id,
        :name,
        :address,
        :latitude,
        :longitude,
        :neighbourhood,
        :city,
        :country_code,
        :opening_hours,
        :accessibility,
        :archived_at
      ]
    }
  end

  @doc "One weekly opening span (ADR-141); `closes` before `opens` crosses midnight."
  def opening_hours_span_schema do
    %Schema{
      title: "OpeningHoursSpan",
      type: :object,
      properties: %{
        weekday: %Schema{
          type: :integer,
          minimum: 1,
          maximum: 7,
          description: "ISO weekday, Monday = 1"
        },
        opens: %Schema{type: :string, pattern: "^([01]\\d|2[0-3]):[0-5]\\d$"},
        closes: %Schema{type: :string, pattern: "^([01]\\d|2[0-3]):[0-5]\\d$"}
      },
      required: [:weekday, :opens, :closes]
    }
  end

  def accessibility_schema,
    do: %Schema{type: :string, enum: Facility.accessibility_features()}

  def location_params_schema do
    %Schema{
      type: :object,
      properties: %{
        name: %Schema{type: :string, minLength: 2, maxLength: 80},
        address: %Schema{type: :string, maxLength: 300, nullable: true},
        latitude: %Schema{type: :number, minimum: -90, maximum: 90, nullable: true},
        longitude: %Schema{type: :number, minimum: -180, maximum: 180, nullable: true},
        neighbourhood: %Schema{type: :string, maxLength: 80, nullable: true},
        city: %Schema{type: :string, maxLength: 80, nullable: true},
        country_code: %Schema{type: :string, pattern: "^[A-Za-z]{2}$", nullable: true},
        opening_hours: %Schema{type: :array, items: opening_hours_span_schema()},
        accessibility: %Schema{type: :array, items: accessibility_schema()}
      }
    }
  end

  def check_in_schema do
    %Schema{
      title: "FacilityCheckIn",
      type: :object,
      properties: %{
        id: @uuid,
        user_id: @uuid,
        nickname: @nullable_string,
        location_id: @nullable_uuid,
        location_name: @nullable_string,
        checked_in_on: %Schema{type: :string, format: :date},
        checked_in_at: %Schema{type: :string, format: :"date-time"},
        source: %Schema{type: :string, enum: ["self", "staff"]},
        recorded_by_id: @nullable_uuid,
        already_checked_in: %Schema{type: :boolean}
      },
      required: [:id, :user_id, :checked_in_on, :checked_in_at, :source]
    }
  end
end
