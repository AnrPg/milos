defmodule PaleeWeb.Schemas.PartnerVerification do
  @moduledoc """
  OpenAPI schemas of Partners verification (ADR-280 §5): the person's
  state and sponsor path, the sponsor's side, and the Palee team's review.
  A phone number only ever appears masked; the selfie only as a 5-minute
  link to the Palee team.
  """

  alias OpenApiSpex.{MediaType, RequestBody, Schema}
  alias Palee.Partners.Verifications

  @uuid %Schema{type: :string, format: :uuid}
  @datetime %Schema{type: :string, format: :"date-time"}
  @nullable_datetime %Schema{type: :string, format: :"date-time", nullable: true}
  @nullable_string %Schema{type: :string, nullable: true}

  def uuid, do: @uuid

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  defp object(title, properties, required),
    do: %Schema{title: title, type: :object, properties: properties, required: required}

  defp list(schema), do: %Schema{type: :array, items: schema}
  defp enum(values), do: %Schema{type: :string, enum: values}
  defp nullable_enum(values), do: %Schema{type: :string, enum: values ++ [nil], nullable: true}

  def person do
    object(
      "PartnerVerificationPerson",
      %{id: @uuid, nickname: @nullable_string, avatar_url: @nullable_string},
      [:id, :nickname, :avatar_url]
    )
  end

  # -- the person ---------------------------------------------------------------

  def eligibility do
    object(
      "PartnerEligibility",
      %{
        status: enum(Enum.map(Verifications.eligibility_statuses(), &Atom.to_string/1)),
        method: nullable_enum(~w(membership sponsors)),
        next_step: nullable_enum(Enum.map(Verifications.eligibility_steps(), &Atom.to_string/1))
      },
      [:status, :method, :next_step]
    )
  end

  def sponsorship do
    object(
      "PartnerSponsorship",
      %{
        id: @uuid,
        person: person(),
        channel: enum(Verifications.sponsorship_channels()),
        status: enum(Verifications.sponsorship_statuses()),
        requested_at: @datetime,
        decided_at: @nullable_datetime
      },
      [:id, :person, :channel, :status, :requested_at, :decided_at]
    )
  end

  def request do
    %Schema{
      object(
        "PartnerVerificationRequest",
        %{
          id: @uuid,
          status: enum(Verifications.request_statuses()),
          consent_at: @nullable_datetime,
          vouches: %Schema{type: :integer},
          sponsors_required: %Schema{type: :integer},
          sponsors: list(sponsorship()),
          phone: %Schema{type: :string, nullable: true, description: "Masked"},
          phone_verified: %Schema{type: :boolean},
          selfie_code: %Schema{
            type: :string,
            pattern: "^[0-9]{4}$",
            description: "Written on paper and held up in the selfie"
          },
          selfie_uploaded_at: @nullable_datetime,
          selfie_expires_at: @nullable_datetime,
          submitted_at: @nullable_datetime,
          decided_at: @nullable_datetime,
          decision_reason: @nullable_string,
          missing: list(enum(~w(consent sponsors phone)))
        },
        [
          :id,
          :status,
          :consent_at,
          :vouches,
          :sponsors_required,
          :sponsors,
          :phone,
          :phone_verified,
          :selfie_code,
          :selfie_uploaded_at,
          :selfie_expires_at,
          :submitted_at,
          :decided_at,
          :decision_reason,
          :missing
        ]
      )
      | nullable: true
    }
  end

  def limits do
    object(
      "PartnerVerificationLimits",
      %{
        sponsors_required: %Schema{type: :integer},
        link_minutes: %Schema{type: :integer},
        code_minutes: %Schema{type: :integer},
        code_attempts: %Schema{type: :integer},
        selfie_content_types: list(%Schema{type: :string}),
        selfie_max_bytes: %Schema{type: :integer},
        selfie_retention_days: %Schema{type: :integer}
      },
      [
        :sponsors_required,
        :link_minutes,
        :code_minutes,
        :code_attempts,
        :selfie_content_types,
        :selfie_max_bytes,
        :selfie_retention_days
      ]
    )
  end

  def overview do
    object(
      "PartnerVerificationOverview",
      %{eligibility: eligibility(), request: request(), limits: limits()},
      [:eligibility, :request, :limits]
    )
  end

  def sponsor_candidates do
    candidate =
      object(
        "PartnerSponsorCandidate",
        %{
          person: person(),
          eligible: %Schema{type: :boolean},
          reason: nullable_enum(~w(not_verified blocked quota penalty self)),
          sponsorship: %Schema{
            type: :object,
            nullable: true,
            properties: %{
              id: @uuid,
              status: enum(Verifications.sponsorship_statuses()),
              channel: enum(Verifications.sponsorship_channels())
            }
          }
        },
        [:person, :eligible, :reason, :sponsorship]
      )

    object(
      "PartnerSponsorCandidates",
      %{
        candidates: list(candidate),
        required: %Schema{type: :integer},
        vouches: %Schema{type: :integer}
      },
      [:candidates, :required, :vouches]
    )
  end

  def sponsor_request,
    do: object("PartnerSponsorRequest", %{sponsor_id: @uuid}, [:sponsor_id])

  def sponsorship_response,
    do: object("PartnerSponsorshipResponse", %{sponsorship: sponsorship()}, [:sponsorship])

  def link do
    object(
      "PartnerSponsorLink",
      %{
        token: %Schema{type: :string, description: "Shown once"},
        path: %Schema{type: :string},
        url: %Schema{type: :string},
        expires_at: @datetime
      },
      [:token, :path, :url, :expires_at]
    )
  end

  def phone_request,
    do:
      object(
        "PartnerPhoneRequest",
        %{phone: %Schema{type: :string, maxLength: 32, description: "Mobile, E.164 or Greek 69…"}},
        [:phone]
      )

  def phone_sent do
    object(
      "PartnerPhoneSent",
      %{phone: %Schema{type: :string}, expires_at: @datetime, code_minutes: %Schema{type: :integer}},
      [:phone, :expires_at, :code_minutes]
    )
  end

  def code_request,
    do: object("PartnerCodeRequest", %{code: %Schema{type: :string, maxLength: 12}}, [:code])

  def selfie_upload_request,
    do:
      object(
        "PartnerSelfieUploadRequest",
        %{content_type: enum(Verifications.selfie_content_types())},
        [:content_type]
      )

  def selfie_upload do
    object(
      "PartnerSelfieUpload",
      %{
        upload_url: %Schema{type: :string},
        method: enum(["PUT"]),
        required_headers: %Schema{type: :object, additionalProperties: %Schema{type: :string}},
        file_key: %Schema{type: :string},
        content_type: %Schema{type: :string},
        max_bytes: %Schema{type: :integer},
        selfie_code: %Schema{type: :string}
      },
      [
        :upload_url,
        :method,
        :required_headers,
        :file_key,
        :content_type,
        :max_bytes,
        :selfie_code
      ]
    )
  end

  def submit_request,
    do:
      object(
        "PartnerVerificationSubmit",
        %{file_key: %Schema{type: :string, maxLength: 300}},
        [:file_key]
      )

  # -- the sponsor --------------------------------------------------------------

  def vouching do
    object(
      "PartnerVouching",
      %{
        can_vouch: %Schema{type: :boolean},
        reason: nullable_enum(~w(not_verified quota penalty)),
        quota: %Schema{type: :integer},
        window_days: %Schema{type: :integer},
        used: %Schema{type: :integer},
        left: %Schema{type: :integer},
        penalty_until: @nullable_datetime
      },
      [:can_vouch, :reason, :quota, :window_days, :used, :left, :penalty_until]
    )
  end

  def vouch_requests do
    item =
      object(
        "PartnerVouchRequest",
        %{id: @uuid, person: person(), requested_at: @datetime},
        [:id, :person, :requested_at]
      )

    object(
      "PartnerVouchRequests",
      %{requests: list(item), vouching: vouching()},
      [:requests, :vouching]
    )
  end

  def vouch_decision_request,
    do:
      object(
        "PartnerVouchDecision",
        %{decision: enum(Verifications.vouch_decisions())},
        [:decision]
      )

  def vouch_result do
    object(
      "PartnerVouchResult",
      %{id: @uuid, status: enum(Verifications.sponsorship_statuses()), decided_at: @nullable_datetime},
      [:id, :status, :decided_at]
    )
  end

  def token_request,
    do: object("PartnerVouchLinkToken", %{token: %Schema{type: :string, maxLength: 128}}, [:token])

  def link_inspection do
    object(
      "PartnerVouchLinkInspection",
      %{
        person: person(),
        expires_at: @datetime,
        can_vouch: %Schema{type: :boolean},
        reason: nullable_enum(~w(partner_sponsor_not_eligible partner_sponsor_quota partner_sponsor_penalty))
      },
      [:person, :expires_at, :can_vouch, :reason]
    )
  end

  # -- the Palee team -----------------------------------------------------------

  def platform_list do
    item =
      object(
        "PlatformPartnerVerificationItem",
        %{
          id: @uuid,
          status: enum(Verifications.request_statuses()),
          person: person(),
          submitted_at: @nullable_datetime,
          selfie_expires_at: @nullable_datetime,
          overdue: %Schema{type: :boolean}
        },
        [:id, :status, :person, :submitted_at, :selfie_expires_at, :overdue]
      )

    object("PlatformPartnerVerifications", %{requests: list(item)}, [:requests])
  end

  def platform_detail do
    sponsor =
      object(
        "PlatformPartnerVerificationSponsor",
        %{person: person(), channel: enum(Verifications.sponsorship_channels()), vouched_at: @nullable_datetime},
        [:person, :channel, :vouched_at]
      )

    object(
      "PlatformPartnerVerification",
      %{
        id: @uuid,
        status: enum(Verifications.request_statuses()),
        person: person(),
        selfie_code: %Schema{type: :string},
        selfie_url: %Schema{type: :string, nullable: true, description: "Valid 5 minutes"},
        selfie_url_expires_in: %Schema{type: :integer},
        selfie_uploaded_at: @nullable_datetime,
        selfie_expires_at: @nullable_datetime,
        phone: %Schema{type: :string, nullable: true, description: "Masked"},
        phone_verified: %Schema{type: :boolean},
        consent_at: @nullable_datetime,
        submitted_at: @nullable_datetime,
        decided_at: @nullable_datetime,
        decision_reason: @nullable_string,
        sponsors: list(sponsor)
      },
      [
        :id,
        :status,
        :person,
        :selfie_code,
        :selfie_url,
        :selfie_url_expires_in,
        :selfie_uploaded_at,
        :selfie_expires_at,
        :phone,
        :phone_verified,
        :consent_at,
        :submitted_at,
        :decided_at,
        :decision_reason,
        :sponsors
      ]
    )
  end

  def platform_decision_request do
    object(
      "PlatformPartnerVerificationDecision",
      %{
        decision: enum(Verifications.review_decisions()),
        reason: %Schema{type: :string, maxLength: 500, nullable: true, description: "Required to reject"}
      },
      [:decision]
    )
  end

  def platform_decision do
    object(
      "PlatformPartnerVerificationDecided",
      %{id: @uuid, status: enum(Verifications.request_statuses()), decided_at: @nullable_datetime},
      [:id, :status, :decided_at]
    )
  end
end
