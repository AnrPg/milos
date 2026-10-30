defmodule PaleeWeb.Schemas.PartnerSuggestions do
  @moduledoc """
  OpenAPI schemas of «Κλείστε μαζί» suggestions for a Partners match
  (ADR-280 §4): the suggestions, proposing one as a plan, «Δεν ταιριάζει»
  feedback and the vendors' daily counters. A suggestion says only whether
  you or your partner booked it, never who else goes.
  """

  alias Palee.Partners.Suggestions
  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  @uuid %Schema{type: :string, format: :uuid}
  @datetime %Schema{type: :string, format: :"date-time"}
  @nullable_string %Schema{type: :string, nullable: true}

  def uuid, do: @uuid

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  defp object(title, properties, required),
    do: %Schema{title: title, type: :object, properties: properties, required: required}

  defp enum(values), do: %Schema{type: :string, enum: values}

  def suggestion do
    object(
      "PartnerSuggestion",
      %{
        key: %Schema{
          type: :string,
          description: "`kind:id`, what feedback names",
          maxLength: 120
        },
        kind: enum(Suggestions.kinds()),
        id: @uuid,
        title: @nullable_string,
        starts_at: @datetime,
        ends_at: %Schema{type: :string, format: :"date-time", nullable: true},
        time_zone: %Schema{
          type: :string,
          nullable: true,
          description: "The activity's own IANA zone; times show in it"
        },
        place: @nullable_string,
        spots_left: %Schema{
          type: :integer,
          nullable: true,
          description: "Free places; null when there is no limit"
        },
        booked_by_me: %Schema{type: :boolean},
        booked_by_partner: %Schema{type: :boolean},
        distances_km: %Schema{
          type: :array,
          items: %Schema{type: :number, nullable: true},
          minItems: 2,
          maxItems: 2,
          description:
            "From your neighbourhood and your partner's, to 0.1 km; null when unknown " <>
              "(a class of a box you both belong to)"
        },
        reasons: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description:
            "Why it is suggested: both_booked, one_booked, shared_time:<early|midday|" <>
              "afternoon|evening|weekend>, level_fit, near_both"
        }
      },
      [
        :key,
        :kind,
        :id,
        :title,
        :starts_at,
        :place,
        :booked_by_me,
        :booked_by_partner,
        :distances_km,
        :reasons
      ]
    )
  end

  def suggestions do
    object(
      "PartnerSuggestions",
      %{
        suggestions: %Schema{
          type: :array,
          items: suggestion(),
          maxItems: 3,
          description: "At most three, best first; empty hides the card («Πάμε μαζί;» stays)"
        }
      },
      [:suggestions]
    )
  end

  def plan_request do
    object(
      "PartnerPlanRequest",
      %{kind: enum(Suggestions.kinds()), id: @uuid},
      [:kind, :id]
    )
  end

  def feedback_request do
    object(
      "PartnerSuggestionFeedbackRequest",
      %{
        key: %Schema{type: :string, minLength: 3, maxLength: 120},
        reason: enum(Suggestions.feedback_reasons())
      },
      [:key, :reason]
    )
  end

  def feedback_response do
    object(
      "PartnerSuggestionFeedback",
      %{key: %Schema{type: :string}, reason: enum(Suggestions.feedback_reasons())},
      [:key, :reason]
    )
  end

  @count %Schema{type: :integer, minimum: 0}

  def stats do
    day =
      object(
        "PartnerSuggestionStatsDay",
        %{
          day: %Schema{type: :string, format: :date},
          shown: @count,
          proposed: @count,
          booked_together: @count,
          feedback: @count
        },
        [:day, :shown, :proposed, :booked_together, :feedback]
      )

    reasons =
      object(
        "PartnerSuggestionFeedbackReasons",
        %{not_near: @count, bad_time: @count, wrong_level: @count, other: @count},
        [:not_near, :bad_time, :wrong_level, :other]
      )

    object(
      "PartnerSuggestionStats",
      %{
        since: %Schema{type: :string, format: :date},
        days: %Schema{type: :array, items: day, description: "Oldest first, one per day"},
        feedback_reasons: reasons
      },
      [:since, :days, :feedback_reasons]
    )
  end
end
