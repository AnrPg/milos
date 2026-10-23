defmodule PaleeWeb.Schemas.Perks do
  @moduledoc "OpenAPI schemas for partner perks (ADR-191)."

  alias OpenApiSpex.Schema
  alias Palee.Perks
  alias PaleeWeb.Schemas.Community

  @uuid %Schema{type: :string, format: :uuid}
  @maybe_uuid %Schema{type: :string, format: :uuid, nullable: true}
  @maybe_date %Schema{type: :string, format: :date, nullable: true}
  @datetime %Schema{type: :string, format: :"date-time"}
  @maybe_datetime %Schema{type: :string, format: :"date-time", nullable: true}
  @string %Schema{type: :string}
  @maybe_string %Schema{type: :string, nullable: true}
  @maybe_integer %Schema{type: :integer, nullable: true, minimum: 1}
  @integer %Schema{type: :integer}
  @boolean %Schema{type: :boolean}
  @maybe_cents %Schema{type: :integer, nullable: true, minimum: 1}

  def body(schema), do: Community.body(schema)

  def status,
    do: %Schema{
      type: :string,
      enum: Perks.statuses(),
      description: "A published perk past `valid_until` reads as expired."
    }

  def redemption_method,
    do: %Schema{
      type: :string,
      enum: Perks.methods(),
      description:
        "Partner-issued (the partner checks the code in its own system): shared_code (default), code_pool (a batch of single-use codes, one per claim), partner_link (an online store link with the code applied), show_membership (no code). Palee-issued: personal_qr (a single-use QR the partner verifies with a signed link)."
    }

  def claim_status, do: %Schema{type: :string, enum: Perks.claim_statuses()}

  # Documents -----------------------------------------------------------------

  def benefit(required \\ [:type]) do
    %Schema{
      title: if(required == [], do: "PerkBenefitPatch", else: "PerkBenefit"),
      type: :object,
      description:
        "percent: `percent`; fixed_amount: `amount_cents` + `currency`; free_item: `item`; buy_x_get_y: `buy_quantity`, `get_quantity` (and `item`); free_text: `text`. Optional for all: `min_spend_cents`, `max_discount_cents`.",
      properties: %{
        schema_version: %Schema{type: :integer, readOnly: true},
        type: %Schema{type: :string, enum: Perks.benefit_types()},
        percent: %Schema{type: :integer, nullable: true, minimum: 1, maximum: 100},
        amount_cents: @maybe_cents,
        currency: %Schema{type: :string, nullable: true, pattern: "^[A-Za-z]{3}$"},
        item: %Schema{type: :string, nullable: true, maxLength: 120},
        buy_quantity: %Schema{type: :integer, nullable: true, minimum: 1, maximum: 100},
        get_quantity: %Schema{type: :integer, nullable: true, minimum: 1, maximum: 100},
        text: %Schema{type: :string, nullable: true, maxLength: 200},
        min_spend_cents: @maybe_cents,
        max_discount_cents: @maybe_cents
      },
      required: required
    }
  end

  def rules do
    %Schema{
      title: "PerkRules",
      type: :object,
      properties: %{
        schema_version: %Schema{type: :integer, readOnly: true},
        valid_from: @maybe_date,
        valid_until: @maybe_date,
        channel: %Schema{type: :string, enum: Perks.channels()},
        stacking: %Schema{type: :string, nullable: true, maxLength: 1000},
        recurring: %Schema{
          type: :array,
          maxItems: 14,
          description: "Weekly windows in the business's local time; none means always.",
          items: %Schema{
            title: "PerkRecurringWindow",
            type: :object,
            properties: %{
              weekdays: %Schema{
                type: :array,
                items: %Schema{type: :integer, minimum: 1, maximum: 7},
                description: "ISO weekdays, 1 = Monday."
              },
              starts_at: %Schema{type: :string, example: "06:00:00"},
              ends_at: %Schema{type: :string, example: "10:00:00"}
            },
            required: [:weekdays, :starts_at, :ends_at]
          }
        },
        limits: %Schema{
          title: "PerkLimits",
          type: :object,
          properties: %{
            max_claims: @maybe_integer,
            max_per_member: %Schema{type: :integer, minimum: 1, maximum: 1000},
            period: %Schema{type: :string, nullable: true, enum: Perks.periods()},
            max_per_period: @maybe_integer,
            max_per_member_per_period: @maybe_integer
          }
        },
        eligibility: %Schema{
          title: "PerkEligibility",
          type: :object,
          description: "Empty lists mean everyone. Memberships are packages.",
          properties: %{
            package_ids: %Schema{type: :array, items: @uuid, maxItems: 200},
            group_ids: %Schema{type: :array, items: @uuid, maxItems: 200},
            min_tenure_days: %Schema{type: :integer, nullable: true, minimum: 1}
          }
        }
      }
    }
  end

  def redemption do
    %Schema{
      title: "PerkRedemptionSettings",
      type: :object,
      description:
        "What the method needs: shared_code (shared_code, and partner_link with `{code}` in the link), link_url (partner_link, https), low_pool_threshold (code_pool, default 10), instructions (any).",
      properties: %{
        schema_version: %Schema{type: :integer, readOnly: true},
        shared_code: %Schema{type: :string, nullable: true, maxLength: 64},
        link_url: %Schema{type: :string, nullable: true, maxLength: 1000},
        low_pool_threshold: %Schema{type: :integer, nullable: true, minimum: 0},
        instructions: %Schema{type: :string, nullable: true, maxLength: 500}
      }
    }
  end

  defp common do
    %{
      id: @uuid,
      organization_id: @uuid,
      partner_name: @string,
      partner_url: @maybe_string,
      partner_address: @maybe_string,
      logo_media_id: @maybe_uuid,
      logo_url: @maybe_string,
      redemption_method: redemption_method(),
      version: %Schema{type: :integer, description: "The version shown."},
      benefit: benefit(),
      benefit_label: %Schema{
        type: :string,
        description: "`10%`, `5.00 EUR`, `Free shaker`, `Buy 2 get 1` or the text."
      },
      rules: rules(),
      terms: @maybe_string,
      instructions: @maybe_string,
      valid_from: @maybe_date,
      valid_until: @maybe_date,
      status: status()
    }
  end

  @common_required ~w(id organization_id partner_name redemption_method version benefit
                      benefit_label rules status)a

  # Staff -------------------------------------------------------------------

  def staff_perk do
    %Schema{
      title: "StaffPerk",
      type: :object,
      properties:
        Map.merge(common(), %{
          redemption: redemption(),
          all_locations: @boolean,
          location_ids: %Schema{type: :array, items: @uuid},
          claims_count: @integer,
          uses_count: @integer,
          remaining: %Schema{
            type: :integer,
            nullable: true,
            description: "Claims left under the overall cap; null when uncapped."
          },
          codes: %Schema{
            title: "PerkCodePool",
            type: :object,
            nullable: true,
            description: "The pool of a code_pool perk; `low` is the low-pool alert.",
            properties: %{total: @integer, free: @integer, low: @boolean},
            required: [:total, :free, :low]
          },
          published_at: @maybe_datetime,
          paused_at: @maybe_datetime,
          expired_at: @maybe_datetime,
          inserted_at: @datetime,
          updated_at: @datetime
        }),
      required:
        @common_required ++
          ~w(redemption all_locations location_ids claims_count uses_count)a
    }
  end

  def staff_list,
    do: %Schema{
      title: "StaffPerkList",
      type: :object,
      properties: %{perks: %Schema{type: :array, items: staff_perk()}},
      required: [:perks]
    }

  def staff_response,
    do: %Schema{
      title: "StaffPerkResponse",
      type: :object,
      properties: %{perk: staff_perk()},
      required: [:perk]
    }

  def versions_response,
    do: %Schema{
      title: "PerkVersionList",
      type: :object,
      properties: %{
        versions: %Schema{
          type: :array,
          items: %Schema{
            title: "PerkVersion",
            type: :object,
            properties: %{
              version: @integer,
              benefit: benefit(),
              benefit_label: @string,
              rules: rules(),
              redemption: redemption(),
              terms: @maybe_string,
              created_by_id: @maybe_uuid,
              inserted_at: @datetime
            },
            required: [:version, :benefit, :benefit_label, :rules, :redemption, :inserted_at]
          }
        }
      },
      required: [:versions]
    }

  @doc "Create (`required` lists the required fields) or update (none required) input."
  def perk_input(required \\ []) do
    create? = required != []

    %Schema{
      title: if(create?, do: "PerkCreate", else: "PerkUpdate"),
      type: :object,
      additionalProperties: false,
      description:
        "Partner fields and branches change the perk; benefit, rules, redemption and terms amend its version until the first claim, then make a new version (claims keep theirs).",
      properties: %{
        partner_name: %Schema{type: :string, minLength: 1, maxLength: 120},
        partner_url: %Schema{type: :string, nullable: true, maxLength: 500},
        partner_address: %Schema{type: :string, nullable: true, maxLength: 300},
        logo_media_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "A ready box_photo upload of the business."
        },
        redemption_method: redemption_method(),
        all_locations: %Schema{
          type: :boolean,
          description: "«Όλα τα καταστήματα» (all-branch staff only); else `location_ids`."
        },
        location_ids: %Schema{type: :array, items: @uuid, maxItems: 200},
        benefit: if(create?, do: benefit(), else: benefit([])),
        rules: rules(),
        redemption: redemption(),
        terms: %Schema{type: :string, nullable: true, maxLength: 4000}
      },
      required: required
    }
  end

  def codes_input,
    do: %Schema{
      title: "PerkCodesInput",
      type: :object,
      additionalProperties: false,
      description: "Either `codes` (pasted) or `csv` (a file's text; the first column is read).",
      properties: %{
        codes: %Schema{
          type: :array,
          minItems: 1,
          maxItems: 5000,
          items: %Schema{type: :string, minLength: 1, maxLength: 64}
        },
        csv: %Schema{type: :string, minLength: 1, maxLength: 1_000_000}
      }
    }

  def codes_response,
    do: %Schema{
      title: "PerkCodesResult",
      type: :object,
      properties: %{
        added: @integer,
        duplicates: @integer,
        total: @integer,
        free: @integer,
        low: @boolean
      },
      required: [:added, :duplicates, :total, :free, :low]
    }

  defp export_row do
    %Schema{
      title: "PerkClaimExportRow",
      type: :object,
      properties: %{
        id: @uuid,
        user_id: @uuid,
        display_name: @maybe_string,
        handle: @maybe_string,
        perk_version: @integer,
        code: @string,
        status: claim_status(),
        claimed_at: @datetime,
        used_at: @maybe_datetime,
        used_via: %Schema{type: :string, nullable: true, enum: ["partner_link", "staff"]},
        revoked_at: @maybe_datetime
      },
      required: [:id, :user_id, :perk_version, :code, :status, :claimed_at]
    }
  end

  def claims_export,
    do: %Schema{
      title: "PerkClaimsExport",
      type: :object,
      properties: %{
        perk: staff_perk(),
        claims: %Schema{type: :array, items: export_row()},
        next: %Schema{
          type: :string,
          nullable: true,
          description: "Cursor of the next page (`after`), null on the last page."
        }
      },
      required: [:perk, :claims]
    }

  def staff_claim_response,
    do: %Schema{
      title: "StaffPerkClaimResponse",
      type: :object,
      properties: %{
        claim: %Schema{
          title: "StaffPerkClaim",
          type: :object,
          properties: %{
            id: @uuid,
            perk_id: @uuid,
            perk_version: @integer,
            user_id: @uuid,
            code: @string,
            status: claim_status(),
            claimed_at: @datetime,
            used_at: @maybe_datetime,
            used_via: @maybe_string,
            revoked_at: @maybe_datetime
          },
          required: [:id, :perk_id, :perk_version, :user_id, :code, :status, :claimed_at]
        }
      },
      required: [:claim]
    }

  # Members ------------------------------------------------------------------

  defp provider do
    %Schema{
      title: "PerkProvider",
      type: :object,
      properties: %{
        organization_id: @uuid,
        name: @maybe_string,
        slug: @maybe_string,
        kind: %Schema{type: :string, enum: ["gym", "coach"]},
        logo_url: @maybe_string
      },
      required: [:organization_id]
    }
  end

  defp verification do
    %Schema{
      title: "PerkVerificationLink",
      type: :object,
      nullable: true,
      description:
        "personal_qr only: the QR encodes the web origin + `path`. Short-lived and single-use; ask for a new one with `POST /api/me/perks/claims/{id}/verification-link`.",
      properties: %{token: @string, path: @string, expires_at: @datetime},
      required: [:token, :path, :expires_at]
    }
  end

  def member_claim do
    %Schema{
      title: "MemberPerkClaim",
      type: :object,
      properties: %{
        id: @uuid,
        perk_id: @uuid,
        perk_version: %Schema{type: :integer, description: "The version you agreed to."},
        organization_id: @uuid,
        provider: provider(),
        partner_name: @string,
        benefit_label: @string,
        redemption_method: redemption_method(),
        terms: @maybe_string,
        instructions: @maybe_string,
        valid_until: @maybe_date,
        partner_url: @maybe_string,
        code: %Schema{
          type: :string,
          nullable: true,
          description:
            "What to give the partner: the shared code, your pool code, the code under your QR; null for show_membership."
        },
        reference: %Schema{type: :string, description: "The claim's own reference."},
        url: %Schema{
          type: :string,
          nullable: true,
          description: "partner_link: the store link with the code applied."
        },
        show_membership: %Schema{
          type: :boolean,
          description: "Show your membership; there is no code."
        },
        status: claim_status(),
        usable: @boolean,
        claimed_at: @datetime,
        used_at: @maybe_datetime,
        verification: verification()
      },
      required: ~w(id perk_id perk_version organization_id provider partner_name benefit_label
           redemption_method reference show_membership status usable claimed_at)a
    }
  end

  def member_perk do
    %Schema{
      title: "MemberPerk",
      type: :object,
      properties:
        Map.merge(common(), %{
          provider: provider(),
          claimable: @boolean,
          unavailable_reason: %Schema{
            type: :string,
            nullable: true,
            enum: ~w(perk_sold_out perk_period_sold_out perk_member_limit perk_member_period_limit
                 perk_outside_hours perk_not_available)
          },
          claim: %Schema{
            allOf: [member_claim()],
            nullable: true,
            description: "Your unused claim."
          }
        }),
      required: @common_required ++ [:provider, :claimable]
    }
  end

  def member_list,
    do: %Schema{
      title: "MemberPerkList",
      type: :object,
      properties: %{perks: %Schema{type: :array, items: member_perk()}},
      required: [:perks]
    }

  def member_claims,
    do: %Schema{
      title: "MemberPerkClaimList",
      type: :object,
      properties: %{claims: %Schema{type: :array, items: member_claim()}},
      required: [:claims]
    }

  def claim_response,
    do: %Schema{
      title: "MemberPerkClaimResponse",
      type: :object,
      properties: %{
        claim: member_claim(),
        created: %Schema{type: :boolean, description: "False when you had already claimed it."}
      },
      required: [:claim]
    }

  # Partner -------------------------------------------------------------------

  def verification_response,
    do: %Schema{
      title: "PerkVerification",
      type: :object,
      description:
        "What the partner's counter sees: the perk, valid or used, the member's first name.",
      properties: %{
        status: %Schema{type: :string, enum: ~w(valid used revoked expired outside_hours)},
        code: @string,
        member_first_name: @maybe_string,
        claimed_at: @datetime,
        used_at: @maybe_datetime,
        perk: %Schema{
          title: "PerkVerificationPerk",
          type: :object,
          properties: %{
            partner_name: @string,
            benefit_label: @string,
            terms: @maybe_string,
            valid_until: @maybe_date
          },
          required: [:partner_name, :benefit_label]
        },
        business: %Schema{
          title: "PerkVerificationBusiness",
          type: :object,
          properties: %{name: @maybe_string, logo_url: @maybe_string}
        }
      },
      required: [:status, :code, :claimed_at, :perk, :business]
    }

  def error,
    do: %Schema{
      title: "PerkError",
      type: :object,
      properties: %{code: @string, error: @string},
      required: [:code]
    }
end
