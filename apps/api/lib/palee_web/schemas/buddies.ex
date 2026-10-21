defmodule PaleeWeb.Schemas.Buddies do
  @moduledoc """
  OpenAPI schemas of Buddy για στήριξη (ADR-160): buddy links, invite
  links, settings, support requests and replies, the member's coach
  summary toggles and the coach's weekly wellness summary. Nothing here
  carries a craving's intensity, causes, outcome or notes.
  """

  alias Palee.Buddies
  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  @uuid %Schema{type: :string, format: :uuid}
  @datetime %Schema{type: :string, format: :"date-time"}
  @nullable_datetime %Schema{type: :string, format: :"date-time", nullable: true}
  @date %Schema{type: :string, format: :date}

  def uuid, do: @uuid

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  def person do
    %Schema{
      title: "BuddyPerson",
      type: :object,
      nullable: true,
      required: [:id, :nickname],
      properties: %{
        id: @uuid,
        nickname: %Schema{type: :string, nullable: true},
        avatar_url: %Schema{type: :string, nullable: true}
      }
    }
  end

  def link do
    %Schema{
      title: "BuddyLink",
      type: :object,
      description:
        "A buddy link seen from your side: `requester` (your buddy) or `buddy` (someone you support). `person` is null for an invite link nobody claimed yet.",
      required: [:id, :role, :status, :person, :via_link, :receives_weekly_summary, :ended_by_me],
      properties: %{
        id: @uuid,
        role: %Schema{type: :string, enum: ["requester", "buddy"]},
        status: %Schema{type: :string, enum: Buddies.link_statuses()},
        person: person(),
        via_link: %Schema{type: :boolean},
        receives_weekly_summary: %Schema{type: :boolean},
        expires_at: @nullable_datetime,
        started_at: @nullable_datetime,
        ended_at: @nullable_datetime,
        ended_by_me: %Schema{type: :boolean},
        unread_messages: %Schema{
          type: :integer,
          description: "Unread messages from the other person in this link's conversation"
        },
        created_at: @datetime
      }
    }
  end

  def message do
    %Schema{
      title: "BuddyMessage",
      type: :object,
      required: [:id, :link_id, :body, :mine, :author, :created_at],
      properties: %{
        id: @uuid,
        link_id: @uuid,
        body: %Schema{type: :string, maxLength: Buddies.message_body_max()},
        mine: %Schema{type: :boolean},
        author: person(),
        created_at: @datetime,
        read_at: @nullable_datetime
      }
    }
  end

  def message_page do
    %Schema{
      title: "BuddyMessagePage",
      type: :object,
      description:
        "A page of the link's conversation, newest first. `read_only` once the link ended: the thread stays readable, nobody can write.",
      required: [:messages, :next_cursor, :read_only, :unread],
      properties: %{
        messages: %Schema{type: :array, items: message()},
        next_cursor: %Schema{type: :string, nullable: true},
        read_only: %Schema{type: :boolean},
        unread: %Schema{type: :integer}
      }
    }
  end

  def message_request do
    %Schema{
      title: "BuddyMessageRequest",
      type: :object,
      required: [:body],
      properties: %{
        body: %Schema{type: :string, minLength: 1, maxLength: Buddies.message_body_max()}
      }
    }
  end

  def message_response do
    %Schema{
      title: "BuddyMessageResponse",
      type: :object,
      required: [:message],
      properties: %{message: message()}
    }
  end

  def messages_read_response do
    %Schema{
      title: "BuddyMessagesReadResponse",
      type: :object,
      required: [:read],
      properties: %{read: %Schema{type: :integer}}
    }
  end

  def wellness_access_log_response do
    %Schema{
      title: "WellnessAccessLog",
      type: :object,
      required: [:entries],
      properties: %{
        entries: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            required: [:id, :read_at, :week_start, :shared, :cravings_shown, :reader],
            properties: %{
              id: @uuid,
              read_at: @datetime,
              week_start: @date,
              shared: %Schema{type: :boolean},
              cravings_shown: %Schema{type: :boolean},
              reader: %Schema{
                type: :object,
                properties: %{id: @uuid, nickname: %Schema{type: :string, nullable: true}}
              },
              organization: %Schema{
                type: :object,
                properties: %{id: @uuid, name: %Schema{type: :string, nullable: true}}
              }
            }
          }
        }
      }
    }
  end

  def link_response do
    %Schema{
      title: "BuddyLinkResponse",
      type: :object,
      required: [:link],
      properties: %{link: link()}
    }
  end

  def settings do
    %Schema{
      title: "BuddySettings",
      type: :object,
      required: [:quiet_hours, :tz, :share_phone, :phone],
      properties: %{
        quiet_hours: %Schema{
          type: :object,
          nullable: true,
          description: "Local times in `tz`; requests still arrive, silently",
          required: [:from, :to],
          properties: %{
            from: %Schema{type: :string, pattern: "^\\d{2}:\\d{2}$"},
            to: %Schema{type: :string, pattern: "^\\d{2}:\\d{2}$"}
          }
        },
        tz: %Schema{type: :string},
        share_phone: %Schema{type: :boolean},
        phone: %Schema{type: :string, nullable: true}
      }
    }
  end

  def settings_response do
    %Schema{
      title: "BuddySettingsResponse",
      type: :object,
      required: [:settings],
      properties: %{settings: settings()}
    }
  end

  def settings_request do
    %Schema{
      title: "BuddySettingsRequest",
      type: :object,
      properties: %{
        quiet_hours: %Schema{
          type: :object,
          nullable: true,
          properties: %{from: %Schema{type: :string}, to: %Schema{type: :string}}
        },
        tz: %Schema{type: :string},
        share_phone: %Schema{type: :boolean},
        phone: %Schema{type: :string, nullable: true}
      }
    }
  end

  def overview do
    %Schema{
      title: "BuddyOverview",
      type: :object,
      required: [:buddies, :supporting, :invitations, :max_buddies, :invite_days, :settings],
      properties: %{
        buddies: %Schema{type: :array, items: link()},
        supporting: %Schema{type: :array, items: link()},
        invitations: %Schema{type: :array, items: link()},
        max_buddies: %Schema{type: :integer},
        invite_days: %Schema{type: :integer},
        settings: settings()
      }
    }
  end

  def candidates_response do
    %Schema{
      title: "BuddyCandidates",
      type: :object,
      required: [:candidates],
      properties: %{
        candidates: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            required: [:person, :relation],
            properties: %{
              person: person(),
              relation: %Schema{type: :string, enum: Buddies.relations()},
              link_status: %Schema{type: :string, nullable: true, enum: ["pending", "active"]}
            }
          }
        }
      }
    }
  end

  def invite_request do
    %Schema{
      title: "BuddyInviteRequest",
      type: :object,
      required: [:user_id],
      properties: %{user_id: @uuid}
    }
  end

  def update_request do
    %Schema{
      title: "BuddyLinkUpdateRequest",
      type: :object,
      required: [:receives_weekly_summary],
      properties: %{receives_weekly_summary: %Schema{type: :boolean}}
    }
  end

  def invite_link_response do
    %Schema{
      title: "BuddyInviteLinkResponse",
      type: :object,
      description: "Shown once: share `url` yourself. Only a digest of the token is kept.",
      required: [:link, :token, :path, :url, :expires_at],
      properties: %{
        link: link(),
        token: %Schema{type: :string},
        path: %Schema{type: :string},
        url: %Schema{type: :string},
        expires_at: @datetime
      }
    }
  end

  def invite_preview do
    %Schema{
      title: "BuddyInvitePreview",
      type: :object,
      required: [:status, :inviter],
      properties: %{
        status: %Schema{type: :string, enum: ["pending", "expired", "unavailable"]},
        expires_at: @nullable_datetime,
        inviter: person()
      }
    }
  end

  def support_create_request do
    %Schema{
      title: "SupportRequestCreateRequest",
      type: :object,
      properties: %{
        message: %Schema{type: :string, nullable: true, maxLength: Buddies.support_message_max()}
      }
    }
  end

  def reply do
    %Schema{
      title: "SupportReply",
      type: :object,
      required: [:id, :kind, :person, :created_at],
      properties: %{
        id: @uuid,
        kind: %Schema{type: :string, enum: Buddies.reply_kinds()},
        text: %Schema{type: :string, nullable: true},
        person: person(),
        created_at: @datetime,
        conversation: %Schema{
          type: :object,
          nullable: true,
          description: "Where the reply was posted in the pair's buddy conversation",
          properties: %{link_id: @uuid, message_id: @uuid}
        }
      }
    }
  end

  def support_request do
    %Schema{
      title: "SupportRequest",
      type: :object,
      description:
        "One «Χρειάζομαι στήριξη». The sender (`role: sender`) sees recipients, quiet hours, replies, the undo window and the no-reply card; a buddy (`role: buddy`) sees the message, who sent it and their own replies.",
      required: [:id, :role, :message, :created_at, :status],
      properties: %{
        id: @uuid,
        role: %Schema{type: :string, enum: ["sender", "buddy"]},
        message: %Schema{type: :string, nullable: true},
        source: %Schema{type: :string, enum: Buddies.support_sources()},
        created_at: @datetime,
        status: %Schema{type: :string, enum: ["sending", "delivered", "undone"]},
        undo_until: @datetime,
        can_undo: %Schema{type: :boolean},
        recipients: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              person: person(),
              quiet_hours: %Schema{type: :boolean},
              replied_at: @nullable_datetime
            }
          }
        },
        quiet_hours: %Schema{
          type: :array,
          description: "Buddies who got it silently (their quiet hours)",
          items: person()
        },
        replies: %Schema{type: :array, items: reply()},
        nudge: %Schema{
          type: :object,
          description:
            "The calm card after ten minutes without a reply; help lines are information, not advice",
          properties: %{
            due: %Schema{type: :boolean},
            due_at: @datetime,
            sent_at: @nullable_datetime,
            suggestions: %Schema{type: :array, items: %Schema{type: :string}},
            breathing_seconds: %Schema{type: :integer},
            can_resend: %Schema{type: :boolean},
            help_lines: %Schema{
              type: :object,
              properties: %{
                path: %Schema{type: :string},
                informational: %Schema{type: :boolean}
              }
            }
          }
        },
        sender: person(),
        delivered_silently: %Schema{type: :boolean},
        quick_replies: %Schema{
          type: :array,
          items: %Schema{type: :string, enum: Buddies.quick_replies()}
        }
      }
    }
  end

  def support_request_response do
    %Schema{
      title: "SupportRequestResponse",
      type: :object,
      required: [:support_request],
      properties: %{support_request: support_request()}
    }
  end

  def support_request_list do
    %Schema{
      title: "SupportRequestList",
      type: :object,
      required: [:support_requests],
      properties: %{support_requests: %Schema{type: :array, items: support_request()}}
    }
  end

  def reply_request do
    %Schema{
      title: "SupportReplyRequest",
      type: :object,
      required: [:kind],
      properties: %{
        kind: %Schema{type: :string, enum: Buddies.reply_kinds()},
        text: %Schema{type: :string, nullable: true, maxLength: 500}
      }
    }
  end

  def reply_response do
    %Schema{
      title: "SupportReplyResponse",
      type: :object,
      required: [:reply, :sender_phone],
      properties: %{
        reply: reply(),
        sender_phone: %Schema{
          type: :string,
          nullable: true,
          description: "Only for `call`, and only when the sender shares their phone with buddies"
        }
      }
    }
  end

  def summary_sharing do
    %Schema{
      title: "WellnessSummarySharing",
      type: :object,
      required: [:wellness, :cravings],
      properties: %{
        wellness: %Schema{type: :boolean, description: "Ευεξία · εβδομαδιαία σύνοψη"},
        cravings: %Schema{type: :boolean, description: "Λιγούρες στη σύνοψη"},
        wellness_since: @nullable_datetime,
        cravings_since: @nullable_datetime
      }
    }
  end

  def summary_sharing_response do
    %Schema{
      title: "WellnessSummarySharingResponse",
      type: :object,
      required: [:sharing],
      properties: %{sharing: summary_sharing()}
    }
  end

  def summary_sharing_request do
    %Schema{
      title: "WellnessSummarySharingRequest",
      type: :object,
      properties: %{wellness: %Schema{type: :boolean}, cravings: %Schema{type: :boolean}}
    }
  end

  def client_summary_response do
    %Schema{
      title: "ClientWellnessSummary",
      type: :object,
      required: [:shared, :summary],
      properties: %{
        shared: %Schema{type: :boolean},
        summary: %Schema{
          type: :object,
          nullable: true,
          required: [:week_start, :week_end, :sleep, :water, :meals, :cravings],
          properties: %{
            week_start: @date,
            week_end: @date,
            allowed_since: @nullable_datetime,
            sleep: %Schema{
              type: :object,
              properties: %{
                nights_on_goal: %Schema{type: :integer},
                nights_logged: %Schema{type: :integer}
              }
            },
            water: %Schema{
              type: :object,
              properties: %{
                days_on_goal: %Schema{type: :integer},
                days_logged: %Schema{type: :integer}
              }
            },
            meals: %Schema{type: :object, properties: %{days_logged: %Schema{type: :integer}}},
            cravings: %Schema{
              type: :object,
              nullable: true,
              description:
                "Only when the member allowed cravings in the summary: count and times",
              properties: %{
                count: %Schema{type: :integer},
                moments: %Schema{
                  type: :array,
                  items: %Schema{
                    type: :object,
                    properties: %{date: @date, time: %Schema{type: :string}}
                  }
                }
              }
            }
          }
        }
      }
    }
  end
end
