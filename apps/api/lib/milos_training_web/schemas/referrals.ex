defmodule MilosTrainingWeb.Schemas.Referrals do
  @moduledoc "OpenAPI schemas for member referrals: «Φέρε φίλο» (ADR-156, P2-M8)."

  alias MilosTrainingWeb.Schemas.Social
  alias OpenApiSpex.Schema

  @uuid %Schema{type: :string, format: :uuid}
  @datetime %Schema{type: :string, format: :"date-time"}
  @maybe_datetime %Schema{type: :string, format: :"date-time", nullable: true}
  @maybe_string %Schema{type: :string, nullable: true}

  def body(schema), do: Social.body(schema)

  def stage,
    do: %Schema{
      type: :string,
      enum: ~w(signed_up event trial joined paid),
      description: "The furthest step the friend reached"
    }

  def status,
    do: %Schema{
      type: :string,
      enum: ~w(open qualified capped expired void),
      description:
        "open: on its way; qualified: the programme's step was reached and the referral opened; capped: over the member's yearly cap; expired: the window ended; void: doesn't earn"
    }

  def channel, do: %Schema{type: :string, enum: ~w(link qr event guest_pass staff)}

  defp person do
    %Schema{
      title: "ReferralPerson",
      type: :object,
      properties: %{id: @uuid, nickname: @maybe_string, avatar_url: @maybe_string},
      required: [:id]
    }
  end

  def gift do
    %Schema{
      title: "ReferralFriendGift",
      type: :object,
      nullable: true,
      description: "What the friend gets; null when the programme gives the friend nothing",
      properties: %{
        type: %Schema{type: :string, enum: ~w(free_days credit custom)},
        value: %Schema{type: :integer, description: "Days for free_days, cents for credit"},
        note: @maybe_string
      },
      required: [:type, :value]
    }
  end

  defp reward_terms do
    %Schema{
      title: "ReferralRewardTerms",
      type: :object,
      properties: %{
        type: %Schema{type: :string, enum: ~w(credit discount free_period manual)},
        value: %Schema{
          type: :integer,
          description: "Cents for credit, percent for discount, days for free_period"
        },
        note: @maybe_string
      },
      required: [:type, :value]
    }
  end

  def program do
    %Schema{
      title: "ReferralProgramTerms",
      type: :object,
      nullable: true,
      description: "The box's active programme; null when it has none",
      properties: %{
        id: @uuid,
        name: %Schema{type: :string},
        reward: reward_terms(),
        gift: gift(),
        qualifying_stage: %Schema{type: :string, enum: ~w(trial paid)},
        attribution_days: %Schema{type: :integer},
        yearly_cap: %Schema{type: :integer, nullable: true}
      },
      required: [:id, :name, :reward, :qualifying_stage, :attribution_days]
    }
  end

  defp reward do
    %Schema{
      title: "ReferralReward",
      type: :object,
      nullable: true,
      description: "The inviter's reward for this friend; null without a programme",
      properties: %{
        type: %Schema{type: :string, enum: ~w(credit discount free_period manual)},
        value: %Schema{type: :integer},
        note: @maybe_string,
        status: %Schema{
          type: :string,
          enum: ~w(upcoming pending approved given rejected capped none)
        },
        applied_at: @maybe_datetime
      },
      required: [:type, :value, :status]
    }
  end

  defp invite_properties do
    %{
      id: @uuid,
      friend: person(),
      stage: stage(),
      stage_at: @datetime,
      status: status(),
      channel: channel(),
      attributed_at: @datetime,
      expires_at: @datetime,
      reward: reward()
    }
  end

  @invite_required [
    :id,
    :friend,
    :stage,
    :stage_at,
    :status,
    :channel,
    :attributed_at,
    :expires_at
  ]

  def invite do
    %Schema{
      title: "ReferralInvite",
      type: :object,
      description: "A friend the member invited, as the member sees them",
      properties: invite_properties(),
      required: @invite_required
    }
  end

  def staff_invite do
    %Schema{
      title: "ReferralInviteForStaff",
      type: :object,
      properties:
        Map.merge(invite_properties(), %{
          referrer: %Schema{person() | nullable: true},
          previous_referrer: %Schema{person() | nullable: true},
          steps: %Schema{
            type: :object,
            properties: %{
              event_at: @maybe_datetime,
              trial_at: @maybe_datetime,
              joined_at: @maybe_datetime,
              paid_at: @maybe_datetime
            }
          },
          new_account: %Schema{type: :boolean},
          community_event_id: %Schema{type: :string, format: :uuid, nullable: true},
          void_reason: @maybe_string,
          notes: @maybe_string,
          reassigned_at: @maybe_datetime,
          referral_event_id: %Schema{type: :string, format: :uuid, nullable: true},
          program: %Schema{
            type: :object,
            nullable: true,
            properties: %{id: @uuid, name: %Schema{type: :string}},
            required: [:id, :name]
          },
          friend_gift: gift(),
          friend_gift_applied_at: @maybe_datetime
        }),
      required: @invite_required ++ [:steps, :new_account]
    }
  end

  defp event do
    %Schema{
      title: "ReferralEvent",
      type: :object,
      description: "An upcoming event a friend can come to",
      properties: %{
        id: @uuid,
        title: %Schema{type: :string},
        starts_at: @datetime,
        ends_at: @datetime,
        price_cents: %Schema{type: :integer},
        currency: %Schema{type: :string},
        place_name: @maybe_string,
        access: %Schema{
          type: :string,
          enum: ~w(open guest_pass),
          description: "open: anyone signed in; guest_pass: as the member's guest"
        }
      },
      required: [:id, :title, :starts_at, :ends_at, :price_cents, :currency, :access]
    }
  end

  def overview do
    %Schema{
      title: "ReferralOverview",
      type: :object,
      properties: %{
        code: %Schema{type: :string},
        path: %Schema{type: :string, description: "The member app path of the invite: /r/<code>"},
        earns_rewards: %Schema{
          type: :boolean,
          description: "Members earn rewards; staff and coaches share the link without one"
        },
        program: program(),
        events: %Schema{type: :array, items: event()},
        invites: %Schema{type: :array, items: invite()},
        totals: %Schema{
          type: :object,
          properties: %{
            invited: %Schema{type: :integer},
            trials: %Schema{type: :integer},
            paid: %Schema{type: :integer}
          },
          required: [:invited, :trials, :paid]
        }
      },
      required: [:code, :path, :earns_rewards, :program, :events, :invites, :totals]
    }
  end

  def code_response do
    %Schema{
      title: "ReferralCodeResponse",
      type: :object,
      properties: %{code: %Schema{type: :string}, path: %Schema{type: :string}},
      required: [:code, :path]
    }
  end

  def public_invite do
    %Schema{
      title: "ReferralInvitePage",
      type: :object,
      properties: %{
        invite: %Schema{
          type: :object,
          properties: %{
            code: %Schema{type: :string},
            box: %Schema{
              type: :object,
              properties: %{
                slug: %Schema{type: :string},
                name: %Schema{type: :string},
                logo_url: @maybe_string,
                primary_color: @maybe_string,
                published: %Schema{type: :boolean},
                cover: %Schema{
                  type: :object,
                  nullable: true,
                  properties: %{
                    id: @uuid,
                    url: %Schema{type: :string},
                    width: %Schema{type: :integer, nullable: true},
                    height: %Schema{type: :integer, nullable: true}
                  },
                  required: [:url]
                },
                disciplines: %Schema{type: :array, items: %Schema{type: :string}},
                neighbourhood: @maybe_string
              },
              required: [:slug, :name, :published, :disciplines]
            },
            inviter: %Schema{
              type: :object,
              properties: %{nickname: @maybe_string, avatar_url: @maybe_string}
            },
            gift: gift(),
            window_days: %Schema{type: :integer, nullable: true},
            trials_enabled: %Schema{type: :boolean}
          },
          required: [:code, :box, :inviter, :gift, :trials_enabled]
        }
      },
      required: [:invite]
    }
  end

  def claim_request do
    %Schema{
      title: "ReferralClaim",
      type: :object,
      properties: %{
        code: %Schema{type: :string, maxLength: 32},
        channel: %Schema{type: :string, enum: ~w(link qr event guest_pass)},
        event_id: %Schema{
          type: :string,
          format: :uuid,
          description: "The event the invite came with (channel event)"
        },
        new_account: %Schema{
          type: :boolean,
          description: "The account was just created from the invite page"
        }
      },
      required: [:code]
    }
  end

  def claim_response do
    %Schema{
      title: "ReferralClaimResult",
      type: :object,
      properties: %{
        outcome: %Schema{
          type: :string,
          enum: ~w(claimed unchanged already_member already_invited self)
        },
        box: %Schema{
          type: :object,
          properties: %{slug: %Schema{type: :string}, name: %Schema{type: :string}},
          required: [:slug, :name]
        }
      },
      required: [:outcome, :box]
    }
  end

  def staff_list do
    %Schema{
      title: "ReferralStaffList",
      type: :object,
      properties: %{
        invites: %Schema{type: :array, items: staff_invite()},
        stats: %Schema{
          type: :object,
          description: "Invites of the last 90 days per status",
          additionalProperties: %Schema{type: :integer}
        }
      },
      required: [:invites, :stats]
    }
  end

  def staff_invite_response do
    %Schema{
      title: "ReferralStaffInviteResponse",
      type: :object,
      properties: %{invite: staff_invite()},
      required: [:invite]
    }
  end

  def note_request do
    %Schema{
      title: "ReferralNote",
      type: :object,
      properties: %{note: %Schema{type: :string, maxLength: 500, nullable: true}}
    }
  end

  def reassign_request do
    %Schema{
      title: "ReferralReassign",
      type: :object,
      properties: %{
        referrer_user_id: @uuid,
        note: %Schema{type: :string, maxLength: 500, nullable: true}
      },
      required: [:referrer_user_id]
    }
  end
end
