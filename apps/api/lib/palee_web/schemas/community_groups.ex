defmodule PaleeWeb.Schemas.CommunityGroups do
  @moduledoc "OpenAPI schemas for member groups, open clubs, «Μέλη» and reports (ADR-143)."

  alias PaleeWeb.Schemas.Community
  alias OpenApiSpex.Schema

  @uuid %Schema{type: :string, format: :uuid}
  @datetime %Schema{type: :string, format: :"date-time"}
  @nullable_datetime %Schema{type: :string, format: :"date-time", nullable: true}

  defdelegate body(schema), to: Community
  defdelegate author(), to: Community

  defp object(title, properties, required),
    do: %Schema{title: title, type: :object, properties: properties, required: required}

  defp list(schema), do: %Schema{type: :array, items: schema}
  defp string(opts \\ []), do: struct(Schema, Keyword.merge([type: :string], opts))

  def group_settings do
    object(
      "CommunityGroupSettings",
      %{
        member_groups: string(enum: Palee.Community.member_group_options()),
        partners_enabled: %Schema{type: :boolean},
        can_propose: %Schema{type: :boolean},
        needs_approval: %Schema{type: :boolean},
        lifecycle: lifecycle()
      },
      [:member_groups, :partners_enabled, :can_propose, :needs_approval, :lifecycle]
    )
  end

  def lifecycle do
    object(
      "CommunityGroupLifecycle",
      %{
        warn_after_days: %Schema{type: :integer},
        archive_after_days: %Schema{type: :integer}
      },
      [:warn_after_days, :archive_after_days]
    )
  end

  def group do
    object(
      "CommunityGroup",
      %{
        id: @uuid,
        club_id: @uuid,
        name: string(),
        description: string(nullable: true),
        join_policy: string(enum: ~w(open request)),
        status: string(enum: ~w(pending active declined)),
        member_count: %Schema{type: :integer},
        request_count: %Schema{
          type: :integer,
          description: "Waiting requests, for those who answer them"
        },
        last_post_at: @nullable_datetime,
        archive_warned_at: @nullable_datetime,
        archived_at: @nullable_datetime,
        membership: string(enum: ~w(none requested member)),
        admin: %Schema{type: :boolean},
        created_by_me: %Schema{type: :boolean},
        can_manage: %Schema{type: :boolean},
        can_report: %Schema{type: :boolean},
        club: %Schema{
          type: :object,
          description: "The gym club it belongs to (in «Βρες»)",
          properties: %{id: @uuid, name: string(), organization_slug: string(nullable: true)}
        },
        members: list(group_member())
      },
      [
        :id,
        :club_id,
        :name,
        :join_policy,
        :status,
        :member_count,
        :request_count,
        :membership,
        :admin,
        :created_by_me,
        :can_manage,
        :can_report
      ]
    )
  end

  def group_member do
    object(
      "CommunityGroupMember",
      %{
        person: author(),
        role: string(enum: ~w(member admin)),
        status: string(enum: ~w(member requested)),
        since: @datetime
      },
      [:person, :role, :status, :since]
    )
  end

  def groups_response do
    object(
      "CommunityGroupsResponse",
      %{
        settings: group_settings(),
        groups: list(group()),
        archived: %{list(group()) | description: "Archived groups you started, to bring back"}
      },
      [:settings, :groups, :archived]
    )
  end

  def group_response, do: object("CommunityGroupResponse", %{group: group()}, [:group])

  def group_request do
    object(
      "CommunityGroupRequest",
      %{
        name: string(minLength: 2, maxLength: 60),
        description: string(maxLength: 200, nullable: true),
        join_policy: string(enum: ~w(open request))
      },
      [:name]
    )
  end

  def group_update_request do
    object(
      "CommunityGroupUpdateRequest",
      %{
        name: string(minLength: 2, maxLength: 60),
        description: string(maxLength: 200, nullable: true),
        join_policy: string(enum: ~w(open request))
      },
      []
    )
  end

  def group_outcome_response do
    object(
      "CommunityGroupOutcome",
      %{group_id: @uuid, outcome: string(enum: ~w(left archived))},
      [:group_id, :outcome]
    )
  end

  def approve_request,
    do: object("CommunityApproveRequest", %{approve: %Schema{type: :boolean}}, [:approve])

  def admin_request,
    do: object("CommunityAdminRequest", %{admin: %Schema{type: :boolean}}, [:admin])

  # Staff -------------------------------------------------------------------

  def staff_group do
    object(
      "CommunityStaffGroup",
      %{
        id: @uuid,
        name: string(),
        description: string(nullable: true),
        join_policy: string(enum: ~w(open request)),
        status: string(enum: ~w(pending active declined)),
        member_count: %Schema{type: :integer},
        created_by: %Schema{allOf: [author()], nullable: true},
        inserted_at: @datetime,
        last_post_at: @nullable_datetime,
        archive_warned_at: @nullable_datetime,
        archived_at: @nullable_datetime
      },
      [:id, :name, :join_policy, :status, :member_count, :inserted_at]
    )
  end

  def staff_groups_response do
    object(
      "CommunityStaffGroupsResponse",
      %{
        settings: group_settings(),
        pending: list(staff_group()),
        live: list(staff_group()),
        archived: list(staff_group())
      },
      [:settings, :pending, :live, :archived]
    )
  end

  def staff_group_response,
    do: object("CommunityStaffGroupResponse", %{group: staff_group()}, [:group])

  def decision_request do
    object("CommunityGroupDecisionRequest", %{decision: string(enum: ~w(approve decline))}, [
      :decision
    ])
  end

  def settings_request do
    object(
      "CommunitySettingsRequest",
      %{
        member_groups: string(enum: Palee.Community.member_group_options()),
        partners_enabled: %Schema{
          type: :boolean,
          description: "Whether the gym's verified clubs offer Partners (ADR-169)"
        }
      },
      []
    )
  end

  def settings_response do
    object(
      "CommunitySettingsResponse",
      %{
        member_groups: string(enum: Palee.Community.member_group_options()),
        partners_enabled: %Schema{type: :boolean},
        lifecycle: lifecycle()
      },
      [:member_groups, :partners_enabled, :lifecycle]
    )
  end

  # Open clubs --------------------------------------------------------------

  def open_club do
    object(
      "CommunityOpenClub",
      %{
        id: @uuid,
        organization_id: @uuid,
        name: string(),
        description: string(nullable: true),
        join_policy: string(enum: Palee.Community.open_club_join_policies()),
        cover_media_id: %Schema{type: :string, format: :uuid, nullable: true},
        cover_url: string(nullable: true),
        member_count: %Schema{type: :integer},
        request_count: %Schema{type: :integer},
        membership: string(enum: ~w(none requested member)),
        role: string(enum: ~w(member staff), nullable: true),
        box: %Schema{
          type: :object,
          properties: %{
            name: string(nullable: true),
            slug: string(nullable: true),
            logo_url: string(nullable: true)
          }
        },
        channels:
          list(%Schema{
            type: :object,
            properties: %{id: @uuid, kind: string(), name: string(nullable: true)},
            required: [:id, :kind]
          }),
        members: list(club_member_row()),
        requests: list(club_member_row())
      },
      [:id, :organization_id, :name, :join_policy, :member_count]
    )
  end

  def club_member_row,
    do: object("CommunityClubMemberRow", %{person: author(), since: @datetime}, [:person, :since])

  def open_club_response, do: object("CommunityOpenClubResponse", %{club: open_club()}, [:club])

  def open_clubs_response,
    do: object("CommunityOpenClubsResponse", %{clubs: list(open_club())}, [:clubs])

  def open_club_request(required \\ [:name]) do
    object(
      if(required == [], do: "CommunityOpenClubUpdateRequest", else: "CommunityOpenClubRequest"),
      %{
        name: string(minLength: 1, maxLength: 80),
        description: string(maxLength: 1000, nullable: true),
        join_policy: string(enum: Palee.Community.open_club_join_policies()),
        cover_media_id: %Schema{type: :string, format: :uuid, nullable: true}
      },
      required
    )
  end

  def archived_response,
    do:
      object("CommunityArchivedResponse", %{club_id: @uuid, archived: %Schema{type: :boolean}}, [
        :club_id,
        :archived
      ])

  def discover_response do
    object("CommunityDiscoverResponse", %{clubs: list(open_club()), groups: list(group())}, [
      :clubs,
      :groups
    ])
  end

  # Μέλη --------------------------------------------------------------------

  def members_response do
    object(
      "CommunityMembersResponse",
      %{
        club_id: @uuid,
        count: %Schema{type: :integer},
        members:
          list(
            object(
              "CommunityMember",
              %{
                id: @uuid,
                nickname: string(nullable: true),
                avatar_url: string(nullable: true),
                coach: %Schema{type: :boolean},
                following: %Schema{type: :boolean}
              },
              [:id, :coach, :following]
            )
          )
      },
      [:club_id, :count, :members]
    )
  end

  # Reports -----------------------------------------------------------------

  def report_request do
    object(
      "CommunityReportRequest",
      %{
        target_type: string(enum: Palee.Community.Report.target_types()),
        target_id: @uuid,
        reason: string(enum: Palee.Community.report_reasons()),
        note: string(maxLength: 500, nullable: true)
      },
      [:target_type, :target_id, :reason]
    )
  end

  def report_response do
    object(
      "CommunityReportResponse",
      %{target_type: string(), target_id: @uuid, reported: %Schema{type: :boolean}},
      [:target_type, :target_id, :reported]
    )
  end

  def report_row do
    object(
      "CommunityReportRow",
      %{
        target_type: string(enum: Palee.Community.Report.target_types()),
        target_id: @uuid,
        channel_id: %Schema{type: :string, format: :uuid, nullable: true},
        author: %Schema{allOf: [author()], nullable: true},
        preview: %Schema{
          type: :object,
          nullable: true,
          description: "What was reported, null when it is already gone",
          properties: %{
            body: string(nullable: true),
            name: string(nullable: true),
            hidden: %Schema{type: :boolean},
            media_status:
              string(
                enum: Palee.Community.post_media_statuses(),
                description: "A post's: processing or failed while its media are not ready"
              ),
            media: list(PaleeWeb.Schemas.Media.post_media())
          }
        },
        report_count: %Schema{type: :integer},
        reasons: %Schema{type: :object, additionalProperties: %Schema{type: :integer}},
        notes: list(string()),
        first_reported_at: @datetime,
        last_reported_at: @datetime
      },
      [:target_type, :target_id, :report_count, :reasons, :notes, :last_reported_at]
    )
  end

  def reports_response,
    do: object("CommunityReportsResponse", %{reports: list(report_row())}, [:reports])

  def report_action_request do
    object(
      "CommunityReportActionRequest",
      %{
        target_type: string(enum: Palee.Community.Report.target_types()),
        target_id: @uuid,
        action: string(enum: Palee.Community.report_actions())
      },
      [:target_type, :target_id, :action]
    )
  end

  def report_action_response do
    object(
      "CommunityReportActionResponse",
      %{
        target_type: string(),
        target_id: @uuid,
        action: string(),
        resolved: %Schema{type: :integer}
      },
      [:target_type, :target_id, :action, :resolved]
    )
  end
end
