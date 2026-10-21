defmodule MilosTrainingWeb.Schemas.CheckIn do
  @moduledoc "OpenAPI schemas for QR check-in, Wallet and connected devices (ADR-155, P2-M7)."

  alias MilosTrainingWeb.Schemas.{Community, Trials}
  alias OpenApiSpex.Schema

  @uuid %Schema{type: :string, format: :uuid}
  @maybe_uuid %Schema{type: :string, format: :uuid, nullable: true}
  @datetime %Schema{type: :string, format: :"date-time"}
  @maybe_datetime %Schema{type: :string, format: :"date-time", nullable: true}
  @maybe_date %Schema{type: :string, format: :date, nullable: true}
  @maybe_string %Schema{type: :string, nullable: true}
  @maybe_integer %Schema{type: :integer, nullable: true}
  @methods ~w(door_qr door_poster door_nfc geofence member_qr wallet desk_search self)

  def body(schema), do: Community.body(schema)
  def error, do: %Schema{type: :object, additionalProperties: true}

  def method, do: %Schema{type: :string, enum: @methods, nullable: true}

  # Shared pieces ---------------------------------------------------------------

  def box do
    %Schema{
      title: "CheckInBox",
      type: :object,
      properties: %{
        organization_id: @uuid,
        slug: %Schema{type: :string},
        name: %Schema{type: :string},
        logo_url: @maybe_string,
        primary_color: @maybe_string
      },
      required: [:organization_id, :slug, :name]
    }
  end

  def location do
    %Schema{
      title: "CheckInLocation",
      type: :object,
      properties: %{id: @uuid, name: %Schema{type: :string}},
      required: [:id, :name]
    }
  end

  def booking do
    %Schema{
      title: "CheckInBooking",
      type: :object,
      properties: %{
        id: @uuid,
        scheduled_class_id: @uuid,
        name: @maybe_string,
        starts_at: @datetime,
        duration_minutes: @maybe_integer,
        location_id: @maybe_uuid,
        kind: %Schema{type: :string, nullable: true, enum: [nil, "member", "guest", "trial"]}
      },
      required: [:id, :scheduled_class_id, :starts_at]
    }
  end

  def class do
    %Schema{
      title: "CheckInClass",
      type: :object,
      properties: %{
        id: @uuid,
        name: @maybe_string,
        starts_at: @datetime,
        duration_minutes: @maybe_integer,
        location_id: @maybe_uuid,
        spots_remaining: @maybe_integer,
        trial_seats: %Schema{type: :integer, nullable: true, description: "Visitor offer only"}
      },
      required: [:id, :starts_at]
    }
  end

  def package do
    %Schema{
      title: "CheckInPackage",
      type: :object,
      nullable: true,
      description:
        "What is left on the member's package; null when the box keeps no package for them",
      properties: %{
        status: @maybe_string,
        name: @maybe_string,
        expires_on: @maybe_date,
        frozen_until: @maybe_date,
        class_visits_left: %Schema{
          type: :integer,
          nullable: true,
          description: "null = unlimited or not part of the package"
        },
        open_gym_visits_left: %Schema{
          type: :integer,
          nullable: true,
          description: "null = unlimited or not part of the package"
        },
        unlimited: %Schema{type: :boolean}
      }
    }
  end

  def check_in do
    %Schema{
      title: "CheckInRecord",
      type: :object,
      nullable: true,
      properties: %{
        kind: %Schema{type: :string, enum: ~w(class open_gym)},
        id: @maybe_uuid,
        at: @maybe_datetime,
        method: method(),
        override: %Schema{type: :boolean},
        booking: %Schema{allOf: [booking()], nullable: true}
      },
      required: [:kind]
    }
  end

  # Door scan -------------------------------------------------------------------

  def scan_request do
    %Schema{
      title: "CheckInScanRequest",
      type: :object,
      description:
        "`location_id` + `code` (the door's rotating QR), `poster_code` (the printed poster) or `nfc_code` (an NFC door tag); or `geofence_token` (the arrival reminder), or `scan_token` from a `choose` answer",
      properties: %{
        location_id: @uuid,
        code: %Schema{type: :string, maxLength: 64},
        poster_code: %Schema{
          type: :string,
          maxLength: 64,
          description: "The printed poster's static code: checks in a booking in its window only"
        },
        nfc_code: %Schema{
          type: :string,
          maxLength: 64,
          description:
            "An NFC door tag's static code (ADR-173): checks in a booking in its window only"
        },
        geofence_token: %Schema{
          type: :string,
          maxLength: 1024,
          description:
            "From GET /api/me/check-in/geofences (ADR-173): checks in a booking in its window only"
        },
        scan_token: %Schema{type: :string, maxLength: 1024},
        booking_id: @uuid
      }
    }
  end

  def trial_offer do
    %Schema{
      title: "CheckInTrialOffer",
      type: :object,
      nullable: true,
      description:
        "Trial classes today and tomorrow at this location; null when the box offers none at the door",
      properties: %{
        enabled: %Schema{type: :boolean},
        approval: %Schema{type: :string, enum: ~w(auto manual)},
        bring_note: @maybe_string,
        horizon_days: @maybe_integer,
        blocked_reason: Trials.blocked_reason(),
        mine: %Schema{type: :object, nullable: true, additionalProperties: true},
        classes: %Schema{type: :array, items: class()}
      },
      required: [:enabled, :classes]
    }
  end

  def scan_response do
    %Schema{
      title: "CheckInScanResult",
      type: :object,
      properties: %{
        outcome: %Schema{
          type: :string,
          enum: ~w(checked_in choose already_checked_in nothing visitor no_booking)
        },
        box: box(),
        location: location(),
        check_in: check_in(),
        undo_token: %Schema{type: :string, description: "Undo within `undo_until`"},
        undo_until: @datetime,
        package: package(),
        choices: %Schema{type: :array, items: booking()},
        scan_token: %Schema{
          type: :string,
          description: "Proof of this scan for 3 minutes, to post again with a booking_id"
        },
        reason: %Schema{
          type: :string,
          nullable: true,
          description: "Why open gym was refused (a finance error code)"
        },
        classes: %Schema{type: :array, items: class(), description: "«Κλείσε θέση»"},
        next_booking: %Schema{allOf: [booking()], nullable: true},
        membership: %Schema{type: :string, enum: ~w(none former member)},
        trial: trial_offer(),
        follow: %Schema{type: :string, enum: ~w(none requested active)}
      },
      required: [:outcome, :box, :location]
    }
  end

  def undo_response do
    %Schema{
      title: "CheckInUndoResult",
      type: :object,
      properties: %{
        kind: %Schema{type: :string, enum: ~w(class open_gym)},
        id: @uuid,
        package: package()
      },
      required: [:kind, :id]
    }
  end

  # Personal QR and desk ----------------------------------------------------------

  def member_code_response do
    %Schema{
      title: "CheckInMemberCode",
      type: :object,
      description:
        "`rotating`: changes every 30 s, no Wallet. `static`: one persistent code (resettable) that can go on a Wallet card.",
      properties: %{
        mode: %Schema{type: :string, enum: ~w(rotating static)},
        code: %Schema{type: :string},
        rotation_seconds: %Schema{type: :integer, nullable: true},
        seconds_until_rotation: %Schema{type: :integer, nullable: true},
        expires_at: %Schema{type: :string, format: :"date-time", nullable: true},
        issued_at: %Schema{type: :string, format: :"date-time", nullable: true},
        wallet_available: %Schema{type: :boolean}
      },
      required: [:mode, :code, :wallet_available]
    }
  end

  def member_code_revoked_response do
    %Schema{
      title: "CheckInMemberCodeRevoked",
      type: :object,
      properties: %{
        user_id: @uuid,
        revoked_codes: %Schema{type: :integer},
        revoked_passes: %Schema{type: :integer}
      },
      required: [:user_id, :revoked_codes, :revoked_passes]
    }
  end

  def poster_response do
    %Schema{
      title: "CheckInPoster",
      type: :object,
      description: "The printed poster of a location: a static QR that only checks in bookings",
      properties: %{
        location: location(),
        enabled: %Schema{type: :boolean},
        code: %Schema{type: :string},
        deep_link: %Schema{
          type: :string,
          description: "`/c/<location>/p/<code>`, what the QR holds"
        },
        rotated_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [:location, :enabled, :code, :deep_link]
    }
  end

  def nfc_tag_response do
    %Schema{
      title: "CheckInNfcTag",
      type: :object,
      description:
        "The NFC door tag of a location (ADR-173): a static link that only checks in bookings",
      properties: %{
        location: location(),
        enabled: %Schema{type: :boolean},
        code: %Schema{type: :string},
        deep_link: %Schema{
          type: :string,
          description: "`/c/<location>/n/<code>`, what the tag holds"
        },
        rotated_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [:location, :enabled, :code, :deep_link]
    }
  end

  def geofences_response do
    window = %Schema{
      type: :object,
      properties: %{
        booking_id: @uuid,
        class_name: @maybe_string,
        starts_at: %Schema{type: :string, format: :"date-time"},
        opens_at: %Schema{type: :string, format: :"date-time"},
        closes_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:booking_id, :starts_at, :opens_at, :closes_at]
    }

    region = %Schema{
      type: :object,
      properties: %{
        id: %Schema{
          type: :string,
          description: "Stable per location, for the phone's region list"
        },
        organization_id: @uuid,
        box_name: %Schema{type: :string},
        location_id: @uuid,
        location_name: @maybe_string,
        latitude: %Schema{type: :number},
        longitude: %Schema{type: :number},
        radius_m: %Schema{type: :integer},
        token: %Schema{type: :string, description: "`geofence_token` for POST /api/check-in/scan"},
        windows: %Schema{type: :array, items: window}
      },
      required: [
        :id,
        :organization_id,
        :box_name,
        :location_id,
        :latitude,
        :longitude,
        :radius_m,
        :token,
        :windows
      ]
    }

    %Schema{
      title: "CheckInGeofences",
      type: :object,
      description:
        "Where the phone reminds the member to check in (ADR-173): locations with a booking in the next hours, only in boxes that allow it",
      properties: %{
        regions: %Schema{type: :array, items: region},
        valid_until: %Schema{type: :string, format: :"date-time"}
      },
      required: [:regions, :valid_until]
    }
  end

  def poster_request do
    %Schema{
      title: "CheckInPosterRequest",
      type: :object,
      properties: %{enabled: %Schema{type: :boolean}},
      required: [:enabled]
    }
  end

  def scan_member_request do
    %Schema{
      title: "CheckInDeskScanRequest",
      type: :object,
      properties: %{
        code: %Schema{type: :string, maxLength: 256, description: "Personal QR or Wallet barcode"},
        location_id: @uuid,
        auto: %Schema{type: :boolean, description: "Check in right away when nothing is wrong"}
      },
      required: [:code]
    }
  end

  def check_in_member_request do
    %Schema{
      title: "CheckInDeskRequest",
      type: :object,
      properties: %{
        method: %Schema{type: :string, enum: ~w(member_qr wallet desk_search)},
        booking_id: @uuid,
        location_id: @uuid,
        override: %Schema{
          type: :boolean,
          description: "«Check-in παρ' όλα αυτά»: only when the owner allows desk overrides"
        }
      }
    }
  end

  def desk_response do
    %Schema{
      title: "CheckInDeskResult",
      type: :object,
      properties: %{
        member: %Schema{
          type: :object,
          properties: %{
            id: @uuid,
            display_name: @maybe_string,
            nickname: @maybe_string,
            avatar_url: @maybe_string
          },
          required: [:id]
        },
        method: %Schema{type: :string, enum: ~w(member_qr wallet desk_search)},
        bookings: %Schema{type: :array, items: booking(), description: "Bookings in the window"},
        decision: %Schema{
          type: :string,
          enum: ~w(class choose already_checked_in open_gym nothing booking_not_in_window)
        },
        already_checked_in: %Schema{
          type: :string,
          nullable: true,
          enum: [nil, "class", "open_gym"]
        },
        package: package(),
        problems: %Schema{
          type: :array,
          items: %Schema{
            type: :string,
            enum: ~w(frozen package_expired unpaid no_spots nothing_to_check_in)
          }
        },
        warnings: %Schema{type: :array, items: %Schema{type: :string, enum: ~w(payment_due)}},
        can_auto_check_in: %Schema{type: :boolean},
        override_allowed: %Schema{type: :boolean},
        checked_in: check_in(),
        organization_id: @uuid
      },
      required: [:member, :decision, :problems, :can_auto_check_in, :override_allowed]
    }
  end

  def visitors_response do
    %Schema{
      title: "CheckInVisitors",
      type: :object,
      properties: %{
        visitors: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              id: @uuid,
              user_id: @uuid,
              nickname: @maybe_string,
              display_name: @maybe_string,
              avatar_url: @maybe_string,
              location_id: @maybe_uuid,
              location_name: @maybe_string,
              scanned_at: @datetime,
              trial_offered: %Schema{type: :boolean}
            },
            required: [:id, :user_id, :scanned_at]
          }
        }
      },
      required: [:visitors]
    }
  end

  # Door display ---------------------------------------------------------------

  def door_response do
    %Schema{
      title: "CheckInDoorDisplay",
      type: :object,
      properties: %{
        location: location(),
        code: %Schema{type: :string},
        deep_link: %Schema{
          type: :string,
          description: "What the QR encodes: /c/<location>/<code>"
        },
        rotation_seconds: %Schema{type: :integer},
        seconds_until_rotation: %Schema{type: :integer},
        codes: %Schema{
          type: :array,
          description:
            "The current code and the next ones, to keep rotating offline (about 2 minutes)",
          items: %Schema{
            type: :object,
            properties: %{
              code: %Schema{type: :string},
              deep_link: %Schema{type: :string},
              shows_from: @datetime,
              valid_until: @datetime
            },
            required: [:code, :deep_link, :shows_from, :valid_until]
          }
        },
        rotated_at: @maybe_datetime,
        next_class: %Schema{allOf: [class()], nullable: true},
        recent_check_ins: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              first_name: @maybe_string,
              kind: %Schema{type: :string, enum: ~w(class open_gym)},
              at: @datetime
            }
          }
        },
        topic: %Schema{
          type: :string,
          description: "Realtime topic with `checked_in` events (first names only)"
        },
        server_time: @datetime
      },
      required: [:location, :code, :deep_link, :rotation_seconds, :codes, :topic]
    }
  end

  # Settings -------------------------------------------------------------------

  def rules do
    %Schema{
      title: "CheckInRules",
      type: :object,
      properties: %{
        window_before_minutes: %Schema{type: :integer, minimum: 0, maximum: 120},
        window_after_minutes: %Schema{type: :integer, minimum: 0, maximum: 120},
        open_gym_requires_package: %Schema{type: :boolean},
        visitor_trial_offer: %Schema{type: :boolean},
        desk_override: %Schema{type: :boolean},
        door_rotation_seconds: %Schema{type: :integer, enum: [15, 30, 60]},
        member_code_mode: %Schema{
          type: :string,
          enum: ~w(rotating static),
          description:
            "Personal QR: rotating (no Wallet) or static (Wallet). Back to rotating revokes static codes and cards."
        },
        geofence_reminder: %Schema{
          type: :boolean,
          description:
            "Members may get an arrival reminder in the app that checks in their booking (ADR-173)"
        }
      }
    }
  end

  def rules_response do
    %Schema{
      title: "CheckInRulesResponse",
      type: :object,
      properties: %{settings: rules()},
      required: [:settings]
    }
  end

  # Wallet and devices ------------------------------------------------------------

  def wallet_pass do
    %Schema{
      title: "WalletPass",
      type: :object,
      properties: %{
        id: @uuid,
        platform: %Schema{type: :string, enum: ~w(apple google)},
        added_at: @datetime,
        last_updated_at: @datetime,
        revoked_at: @maybe_datetime,
        active: %Schema{type: :boolean},
        box: %Schema{
          type: :object,
          properties: %{organization_id: @uuid, slug: @maybe_string, name: @maybe_string}
        }
      },
      required: [:id, :platform, :added_at, :active]
    }
  end

  def wallet_add_request do
    %Schema{
      title: "WalletAddRequest",
      type: :object,
      properties: %{platform: %Schema{type: :string, enum: ~w(apple google)}},
      required: [:platform]
    }
  end

  def wallet_add_response do
    %Schema{
      title: "WalletAddResult",
      type: :object,
      properties: %{
        pass: wallet_pass(),
        download_url: %Schema{
          type: :string,
          nullable: true,
          description: "Apple: open within 10 minutes to add the .pkpass"
        },
        save_url: %Schema{type: :string, nullable: true, description: "Google: Save to Wallet"}
      },
      required: [:pass]
    }
  end

  def wallet_pass_response do
    %Schema{
      title: "WalletPassResponse",
      type: :object,
      properties: %{pass: wallet_pass()},
      required: [:pass]
    }
  end

  def devices_response do
    %Schema{
      title: "ConnectedDevices",
      type: :object,
      properties: %{
        wallet: %Schema{
          type: :object,
          properties: %{
            platforms: %Schema{
              type: :object,
              description: "Whether this server can issue cards per platform",
              properties: %{apple: %Schema{type: :boolean}, google: %Schema{type: :boolean}}
            },
            passes: %Schema{type: :array, items: wallet_pass()}
          },
          required: [:platforms, :passes]
        },
        calendar: %Schema{
          type: :object,
          properties: %{
            https_url: %Schema{type: :string},
            webcal_url: %Schema{type: :string},
            download_url: %Schema{type: :string},
            help: %Schema{type: :object, additionalProperties: %Schema{type: :string}}
          },
          required: [:https_url, :webcal_url]
        },
        integrations: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            description:
              "Garmin (ADR-161) also carries configured, capability, sync_prefs, backfill_day_options and connection; Apple Health and Health Connect (ADR-172) carry sync_prefs, history_days and connection",
            properties: %{
              provider: %Schema{type: :string, enum: ~w(garmin apple_health health_connect)},
              status: %Schema{
                type: :string,
                enum: ~w(connected disconnected unavailable native_only error)
              },
              configured: %Schema{type: :boolean},
              capability: %Schema{type: :string, enum: ~w(available not_configured)},
              sync_prefs: MilosTrainingWeb.Schemas.Devices.sync_prefs(),
              backfill_day_options: %Schema{type: :array, items: %Schema{type: :integer}},
              history_days: %Schema{type: :integer},
              connection: %Schema{
                nullable: true,
                oneOf: [
                  MilosTrainingWeb.Schemas.Devices.garmin_connection(),
                  MilosTrainingWeb.Schemas.PhoneHealth.connection()
                ]
              }
            },
            required: [:provider, :status]
          }
        }
      },
      required: [:wallet, :calendar, :integrations]
    }
  end
end
