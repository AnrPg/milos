defmodule MilosTrainingWeb.AdminFinanceController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{
    ApplyFinanceCreditToInvoice,
    ApplyFinanceCreditToPayment,
    AssignFinanceMemberPackage,
    CreateFinanceInvoice,
    CreateFinanceManualCredit,
    CreateFinancePackage,
    CreateFinancePromotion,
    CreateFinancePromotionCode,
    CreateFinanceReferralEvent,
    CreateFinanceReferralProgram,
    CreateFinanceReferralReward,
    GetAdminFinanceSummary,
    GetFinanceOperationalQueues,
    GetFinancePackage,
    GetFinanceMemberProfile,
    GenerateFinanceRenewalInvoice,
    IssueFinanceInvoice,
    ListFinanceMembers,
    ListFinancePackages,
    ListFinancePromotionCodes,
    ListFinancePromotions,
    ListFinanceReferralPrograms,
    ListFinanceReferrals,
    ListFinanceReferralRewards,
    RecordFinancePayment,
    RedeemFinancePromotion,
    ReverseFinanceCreditLedgerEntry,
    ReverseFinancePayment,
    UpdateFinanceMember,
    UpdateFinancePackage,
    UpdateFinanceReferralProgram,
    UpdateFinanceReferralRewardStatus,
    UpdateFinanceReferralStatus,
    VoidFinanceInvoice
  }

  alias MilosTraining.Infrastructure.Storage.MinioStorage
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}
  alias MilosTrainingWeb.Schemas.AdminDrillDown

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Admin Finance"])
  security([%{"bearerAuth" => []}])

  @open_object %Schema{type: :object, additionalProperties: true}
  @list_response %Schema{type: :object, additionalProperties: true}
  @drill_down_schema AdminDrillDown.finance_drill_down_schema()
  @member_profile_response %Schema{
    type: :object,
    properties: %{drill_down: @drill_down_schema},
    required: [:drill_down],
    additionalProperties: true
  }
  @id_parameter %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }
  @request_body %RequestBody{
    required: true,
    content: %{"application/json" => %MediaType{schema: @open_object}}
  }
  @allowance_config_schema %Schema{
    type: :object,
    additionalProperties: false,
    required: [:limit, :period],
    properties: %{
      limit: %Schema{
        oneOf: [
          %Schema{type: :integer, minimum: 0},
          %Schema{type: :string, enum: ["unlimited"]}
        ]
      },
      period: %Schema{
        type: :string,
        enum: ["calendar_week", "calendar_month", "subscription_period"]
      },
      counted_kinds: %Schema{type: :array, items: %Schema{type: :string}}
    }
  }
  @entitlement_params_schema %Schema{
    type: :object,
    additionalProperties: false,
    required: [:entitlement_version, :channels, :capabilities, :allowances],
    properties: %{
      entitlement_version: %Schema{type: :integer, enum: [1]},
      channels: %Schema{
        type: :array,
        uniqueItems: true,
        items: %Schema{
          type: :string,
          enum: ["in_person", "workout_library", "personal_programming", "coach_messaging"]
        }
      },
      capabilities: %Schema{
        type: :array,
        uniqueItems: true,
        items: %Schema{
          type: :string,
          enum: [
            "book_classes",
            "execute_class_workouts",
            "execute_library_workouts",
            "execute_assigned_workouts",
            "receive_coaching_touchpoints"
          ]
        }
      },
      allowances: %Schema{
        type: :object,
        additionalProperties: false,
        properties: %{
          class_visits: @allowance_config_schema,
          coaching_touchpoints: @allowance_config_schema
        }
      }
    }
  }
  @package_properties %{
    code: %Schema{type: :string},
    name: %Schema{type: :string},
    description: %Schema{type: :string, nullable: true},
    family: %Schema{type: :string},
    billing_period: %Schema{
      type: :string,
      enum: ["monthly", "quarterly", "annual", "custom"]
    },
    base_price_cents: %Schema{type: :integer, minimum: 0},
    currency: %Schema{type: :string},
    tags: %Schema{type: :array, items: %Schema{type: :string}},
    params: @entitlement_params_schema,
    active: %Schema{type: :boolean}
  }
  @create_package_request_body %RequestBody{
    required: true,
    content: %{
      "application/json" => %MediaType{
        schema: %Schema{
          type: :object,
          properties: @package_properties,
          required: [:code, :name, :family, :billing_period],
          additionalProperties: false
        }
      }
    }
  }
  @update_package_request_body %RequestBody{
    required: true,
    content: %{
      "application/json" => %MediaType{
        schema: %Schema{
          type: :object,
          properties: @package_properties,
          additionalProperties: false
        }
      }
    }
  }
  @promotion_campaign_request_body %RequestBody{
    required: true,
    content: %{
      "application/json" => %MediaType{
        schema: %Schema{
          type: :object,
          properties: %{
            name: %Schema{type: :string},
            description: %Schema{type: :string, nullable: true},
            starts_on: %Schema{type: :string, format: :date, nullable: true},
            ends_on: %Schema{type: :string, format: :date, nullable: true},
            active: %Schema{type: :boolean},
            params: %Schema{type: :object, additionalProperties: true}
          },
          required: [:name],
          additionalProperties: false
        }
      }
    }
  }
  @referral_program_request_body %RequestBody{
    required: true,
    content: %{
      "application/json" => %MediaType{
        schema: %Schema{
          type: :object,
          properties: %{
            name: %Schema{type: :string},
            description: %Schema{type: :string, nullable: true},
            active: %Schema{type: :boolean},
            reward_type: %Schema{
              type: :string,
              enum: ["credit", "discount", "free_period", "manual"]
            },
            reward_value: %Schema{type: :integer, minimum: 0},
            params: %Schema{type: :object, additionalProperties: true}
          },
          required: [:name, :reward_type, :reward_value],
          additionalProperties: false
        }
      }
    }
  }
  @update_referral_program_request_body %RequestBody{
    required: true,
    content: %{
      "application/json" => %MediaType{
        schema: %Schema{
          type: :object,
          properties: %{
            name: %Schema{type: :string},
            description: %Schema{type: :string, nullable: true},
            active: %Schema{type: :boolean},
            reward_type: %Schema{
              type: :string,
              enum: ["credit", "discount", "free_period", "manual"]
            },
            reward_value: %Schema{type: :integer, minimum: 0},
            params: %Schema{type: :object, additionalProperties: true}
          },
          additionalProperties: false
        }
      }
    }
  }
  @referral_event_request_body %RequestBody{
    required: true,
    content: %{
      "application/json" => %MediaType{
        schema: %Schema{
          type: :object,
          properties: %{
            referral_program_id: %Schema{type: :string, format: :uuid},
            referrer_user_id: %Schema{type: :string, format: :uuid},
            referred_user_id: %Schema{type: :string, format: :uuid},
            membership_id: %Schema{type: :string, format: :uuid},
            signup_source_snapshot: %Schema{type: :string},
            notes: %Schema{type: :string, nullable: true},
            params: %Schema{type: :object, additionalProperties: true}
          },
          required: [:referral_program_id, :referrer_user_id, :referred_user_id, :membership_id],
          additionalProperties: false
        }
      }
    }
  }
  @referral_reward_request_body %RequestBody{
    required: true,
    content: %{
      "application/json" => %MediaType{
        schema: %Schema{
          type: :object,
          properties: %{
            reward_type: %Schema{
              type: :string,
              enum: ["credit", "discount", "free_period", "manual"],
              nullable: true
            },
            reward_value: %Schema{type: :integer, minimum: 0, nullable: true},
            params: %Schema{type: :object, additionalProperties: true, nullable: true}
          },
          additionalProperties: false
        }
      }
    }
  }

  @invoice_upload_url_request_body %RequestBody{
    required: true,
    content: %{
      "application/json" => %MediaType{
        schema: %Schema{
          type: :object,
          properties: %{
            file_name: %Schema{type: :string},
            content_type: %Schema{type: :string}
          },
          required: [:file_name, :content_type],
          additionalProperties: false
        }
      }
    }
  }
  @promotion_code_request_body %RequestBody{
    required: true,
    content: %{
      "application/json" => %MediaType{
        schema: %Schema{
          type: :object,
          properties: %{
            code: %Schema{type: :string},
            discount_type: %Schema{
              type: :string,
              enum: ["percent", "fixed_amount", "free_period", "manual"]
            },
            discount_value: %Schema{type: :integer, minimum: 0},
            max_redemptions: %Schema{type: :integer, minimum: 1, nullable: true},
            active: %Schema{type: :boolean, nullable: true},
            params: %Schema{type: :object, additionalProperties: true, nullable: true}
          },
          required: [:code, :discount_type, :discount_value],
          additionalProperties: false
        }
      }
    }
  }
  @credit_request_body %RequestBody{
    required: true,
    content: %{
      "application/json" => %MediaType{
        schema: %Schema{
          type: :object,
          properties: %{
            amount_cents: %Schema{type: :integer, minimum: 1},
            description: %Schema{type: :string, nullable: true},
            reason: %Schema{type: :string, nullable: true},
            reversal_type: %Schema{
              type: :string,
              enum: ["refund", "payment_reversal", "waiver_reversal"],
              nullable: true
            },
            request_id: %Schema{type: :string, format: :uuid, nullable: true}
          },
          required: [:amount_cents],
          additionalProperties: false
        }
      }
    }
  }
  @invoice_line_schema %Schema{
    type: :object,
    properties: %{
      line_type: %Schema{
        type: :string,
        enum: ["membership_package", "manual_charge", "discount", "adjustment"],
        nullable: true
      },
      description: %Schema{type: :string},
      quantity: %Schema{type: :integer, minimum: 1, nullable: true},
      unit_amount_cents: %Schema{type: :integer, minimum: 0},
      discount_cents: %Schema{type: :integer, minimum: 0, nullable: true},
      membership_package_subscription_id: %Schema{
        type: :string,
        format: :uuid,
        nullable: true
      },
      package_code_snapshot: %Schema{type: :string, nullable: true},
      package_family_snapshot: %Schema{type: :string, nullable: true},
      params: %Schema{type: :object, additionalProperties: true, nullable: true}
    },
    required: [:description, :unit_amount_cents],
    additionalProperties: false
  }
  @invoice_request_body %RequestBody{
    required: true,
    content: %{
      "application/json" => %MediaType{
        schema: %Schema{
          type: :object,
          properties: %{
            amount_cents: %Schema{type: :integer, minimum: 1, nullable: true},
            description: %Schema{type: :string, nullable: true},
            notes: %Schema{type: :string, nullable: true},
            due_date: %Schema{type: :string, format: :date, nullable: true},
            issue_date: %Schema{type: :string, format: :date, nullable: true},
            service_period_start: %Schema{type: :string, format: :date, nullable: true},
            service_period_end: %Schema{type: :string, format: :date, nullable: true},
            line_type: %Schema{
              type: :string,
              enum: ["membership_package", "manual_charge", "discount", "adjustment"],
              nullable: true
            },
            discount_cents: %Schema{type: :integer, minimum: 0, nullable: true},
            membership_package_subscription_id: %Schema{
              type: :string,
              format: :uuid,
              nullable: true
            },
            lines: %Schema{
              type: :array,
              minItems: 1,
              items: @invoice_line_schema,
              nullable: true
            },
            params: %Schema{type: :object, additionalProperties: true, nullable: true}
          },
          additionalProperties: false
        }
      }
    }
  }

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true]
       when action in [
              :create_promotion_code,
              :create_package,
              :update_package,
              :create_promotion,
              :create_referral_program,
              :create_referral,
              :create_referral_reward,
              :create_manual_credit,
              :create_invoice,
              :apply_credit_to_payment,
              :apply_credit_to_invoice,
              :reverse_payment,
              :reverse_credit_ledger_entry
            ]

  operation(:summary,
    summary: "Fetch finance analytics summary",
    responses: [ok: {"Finance summary", "application/json", @open_object}]
  )

  def summary(conn, _params) do
    with {:ok, payload} <- GetAdminFinanceSummary.call() do
      json(conn, payload)
    end
  end

  operation(:packages,
    summary: "List membership packages",
    responses: [ok: {"Membership packages", "application/json", @list_response}]
  )

  def packages(conn, _params) do
    with {:ok, payload} <- ListFinancePackages.call() do
      json(conn, payload)
    end
  end

  operation(:operational_queues,
    summary: "Fetch operational finance queues",
    responses: [ok: {"Operational finance queues", "application/json", @open_object}]
  )

  def operational_queues(conn, params) do
    with {:ok, payload} <- GetFinanceOperationalQueues.call(params) do
      json(conn, payload)
    end
  end

  operation(:package,
    summary: "Fetch a membership package",
    parameters: [@id_parameter],
    responses: [ok: {"Membership package", "application/json", @open_object}]
  )

  def package(conn, params) do
    with {:ok, payload} <- GetFinancePackage.call(param_id(params)) do
      json(conn, payload)
    end
  end

  operation(:create_package,
    summary: "Create a membership package",
    request_body: @create_package_request_body,
    responses: [created: {"Membership package", "application/json", @open_object}]
  )

  def create_package(conn, params) do
    with {:ok, package} <- CreateFinancePackage.call(body_params(conn, params)) do
      conn
      |> put_status(:created)
      |> json(%{package: package})
    end
  end

  operation(:update_package,
    summary: "Update a membership package",
    parameters: [@id_parameter],
    request_body: @update_package_request_body,
    responses: [ok: {"Membership package", "application/json", @open_object}]
  )

  def update_package(conn, params) do
    with {:ok, package} <- UpdateFinancePackage.call(param_id(params), body_params(conn, params)) do
      json(conn, %{package: package})
    end
  end

  operation(:members,
    summary: "List all members with finance summary",
    responses: [ok: {"Members list", "application/json", @list_response}]
  )

  def members(conn, params) do
    with {:ok, payload} <- ListFinanceMembers.call(params) do
      json(conn, payload)
    end
  end

  operation(:member,
    summary: "Fetch a user's finance profile",
    parameters: [@id_parameter],
    responses: [
      ok: {"Member finance profile", "application/json", @member_profile_response},
      not_found:
        {"Not found", "application/json",
         %Schema{
           type: :object,
           properties: %{error: %Schema{type: :string}},
           required: [:error]
         }},
      forbidden:
        {"Forbidden", "application/json",
         %Schema{
           type: :object,
           properties: %{error: %Schema{type: :string}},
           required: [:error]
         }}
    ]
  )

  def member(conn, params) do
    with {:ok, profile} <- GetFinanceMemberProfile.call(param_id(params)) do
      json(conn, profile)
    end
  end

  operation(:update_member,
    summary: "Create or update a user's membership profile",
    parameters: [@id_parameter],
    request_body: @request_body,
    responses: [ok: {"Membership", "application/json", @open_object}]
  )

  def update_member(conn, params) do
    with {:ok, membership} <-
           UpdateFinanceMember.call(param_id(params), body_params(conn, params)) do
      json(conn, %{membership: membership})
    end
  end

  operation(:assign_package,
    summary: "Assign a package to a user's membership",
    parameters: [@id_parameter],
    request_body: @request_body,
    responses: [created: {"Package subscription", "application/json", @open_object}]
  )

  def assign_package(conn, params) do
    with {:ok, subscription} <-
           AssignFinanceMemberPackage.call(param_id(params), body_params(conn, params)) do
      conn
      |> put_status(:created)
      |> json(%{package_subscription: subscription})
    end
  end

  operation(:record_payment,
    summary: "Record a manual membership payment",
    parameters: [@id_parameter],
    request_body: @request_body,
    responses: [created: {"Membership payment", "application/json", @open_object}]
  )

  def record_payment(conn, params) do
    with {:ok, payment} <- RecordFinancePayment.call(param_id(params), body_params(conn, params)) do
      conn
      |> put_status(:created)
      |> json(%{payment: payment})
    end
  end

  operation(:create_invoice,
    summary: "Create a manual finance invoice for a user's membership",
    parameters: [@id_parameter],
    request_body: @invoice_request_body,
    responses: [created: {"Finance invoice", "application/json", @open_object}]
  )

  def create_invoice(conn, params) do
    with {:ok, invoice} <-
           CreateFinanceInvoice.call(
             param_id(params),
             current_user_id(conn),
             body_params(conn, params)
           ) do
      conn
      |> put_status(:created)
      |> json(%{invoice: invoice})
    end
  end

  operation(:generate_renewal_invoice,
    summary: "Generate a renewal invoice from a user's active membership package",
    parameters: [@id_parameter],
    request_body: @request_body,
    responses: [created: {"Finance invoice", "application/json", @open_object}]
  )

  def generate_renewal_invoice(conn, params) do
    with {:ok, invoice} <-
           GenerateFinanceRenewalInvoice.call(
             param_id(params),
             current_user_id(conn),
             body_params(conn, params)
           ) do
      conn
      |> put_status(:created)
      |> json(%{invoice: invoice})
    end
  end

  operation(:issue_invoice,
    summary: "Issue a draft finance invoice",
    parameters: [@id_parameter],
    request_body: @request_body,
    responses: [ok: {"Finance invoice", "application/json", @open_object}]
  )

  def issue_invoice(conn, params) do
    with {:ok, invoice} <-
           IssueFinanceInvoice.call(
             param_id(params),
             current_user_id(conn),
             body_params(conn, params)
           ) do
      json(conn, %{invoice: invoice})
    end
  end

  operation(:update_invoice,
    summary: "Update due_date and/or notes on a finance invoice",
    parameters: [@id_parameter],
    request_body: @request_body,
    responses: [ok: {"Finance invoice", "application/json", @open_object}]
  )

  def update_invoice(conn, params) do
    invoice_id = param_id(params)
    body = body_params(conn, params)

    with {:ok, invoice} <- MilosTraining.Finance.update_invoice(invoice_id, body) do
      json(conn, %{invoice: invoice})
    end
  end

  operation(:void_invoice,
    summary: "Void a finance invoice",
    parameters: [@id_parameter],
    request_body: @request_body,
    responses: [ok: {"Finance invoice", "application/json", @open_object}]
  )

  def void_invoice(conn, params) do
    with {:ok, invoice} <-
           VoidFinanceInvoice.call(
             param_id(params),
             current_user_id(conn),
             body_params(conn, params)
           ) do
      json(conn, %{invoice: invoice})
    end
  end

  operation(:create_manual_credit,
    summary: "Grant manual credit to a user's membership",
    parameters: [@id_parameter],
    request_body: @credit_request_body,
    responses: [created: {"Credit ledger entry", "application/json", @open_object}]
  )

  def create_manual_credit(conn, params) do
    with {:ok, entry} <-
           CreateFinanceManualCredit.call(
             param_id(params),
             current_user_id(conn),
             body_params(conn, params)
           ) do
      conn
      |> put_status(:created)
      |> json(%{credit_ledger_entry: entry})
    end
  end

  operation(:apply_credit_to_payment,
    summary: "Apply available credit to a membership payment",
    parameters: [
      @id_parameter,
      %Parameter{
        name: :payment_id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: @credit_request_body,
    responses: [created: {"Credit ledger entry", "application/json", @open_object}]
  )

  def apply_credit_to_payment(conn, params) do
    with {:ok, entry} <-
           ApplyFinanceCreditToPayment.call(
             param_id(params),
             params["payment_id"] || params[:payment_id],
             current_user_id(conn),
             body_params(conn, params)
           ) do
      conn
      |> put_status(:created)
      |> json(%{credit_ledger_entry: entry})
    end
  end

  operation(:apply_credit_to_invoice,
    summary: "Apply available credit to a finance invoice",
    parameters: [
      @id_parameter,
      %Parameter{
        name: :invoice_id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: @credit_request_body,
    responses: [created: {"Credit ledger entry", "application/json", @open_object}]
  )

  def apply_credit_to_invoice(conn, params) do
    with {:ok, entry} <-
           ApplyFinanceCreditToInvoice.call(
             param_id(params),
             params["invoice_id"] || params[:invoice_id],
             current_user_id(conn),
             body_params(conn, params)
           ) do
      conn
      |> put_status(:created)
      |> json(%{credit_ledger_entry: entry})
    end
  end

  operation(:reverse_payment,
    summary: "Record an audited refund or reversal for a membership payment",
    parameters: [
      @id_parameter,
      %Parameter{
        name: :payment_id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: @credit_request_body,
    responses: [created: {"Payment reversal", "application/json", @open_object}]
  )

  def reverse_payment(conn, params) do
    with {:ok, reversal} <-
           ReverseFinancePayment.call(
             param_id(params),
             params["payment_id"] || params[:payment_id],
             current_user_id(conn),
             body_params(conn, params)
           ) do
      conn
      |> put_status(:created)
      |> json(%{payment_reversal: reversal})
    end
  end

  operation(:reverse_credit_ledger_entry,
    summary: "Reverse an applied credit ledger entry and restore member credit",
    parameters: [
      @id_parameter,
      %Parameter{
        name: :credit_ledger_entry_id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: @credit_request_body,
    responses: [created: {"Credit ledger reversal", "application/json", @open_object}]
  )

  def reverse_credit_ledger_entry(conn, params) do
    with {:ok, entry} <-
           ReverseFinanceCreditLedgerEntry.call(
             param_id(params),
             params["credit_ledger_entry_id"] || params[:credit_ledger_entry_id],
             current_user_id(conn),
             body_params(conn, params)
           ) do
      conn
      |> put_status(:created)
      |> json(%{credit_ledger_entry: entry})
    end
  end

  operation(:redeem_promotion,
    summary: "Record a promotion redemption for a user's membership",
    parameters: [@id_parameter],
    request_body: @request_body,
    responses: [created: {"Promotion redemption", "application/json", @open_object}]
  )

  def redeem_promotion(conn, params) do
    with {:ok, redemption} <-
           RedeemFinancePromotion.call(param_id(params), body_params(conn, params)) do
      conn
      |> put_status(:created)
      |> json(%{promotion_redemption: redemption})
    end
  end

  operation(:promotions,
    summary: "List promotion campaigns",
    responses: [ok: {"Promotion campaigns", "application/json", @list_response}]
  )

  def promotions(conn, _params) do
    with {:ok, payload} <- ListFinancePromotions.call() do
      json(conn, payload)
    end
  end

  operation(:create_promotion,
    summary: "Create a promotion campaign",
    request_body: @promotion_campaign_request_body,
    responses: [created: {"Promotion campaign", "application/json", @open_object}]
  )

  def create_promotion(conn, params) do
    with {:ok, campaign} <- CreateFinancePromotion.call(body_params(conn, params)) do
      conn
      |> put_status(:created)
      |> json(%{promotion_campaign: campaign})
    end
  end

  operation(:promotion_codes,
    summary: "List promotion codes for a campaign",
    parameters: [@id_parameter],
    responses: [ok: {"Promotion codes", "application/json", @list_response}]
  )

  def promotion_codes(conn, params) do
    with {:ok, payload} <- ListFinancePromotionCodes.call(param_id(params)) do
      json(conn, payload)
    end
  end

  operation(:create_promotion_code,
    summary: "Create a promotion code for a campaign",
    parameters: [@id_parameter],
    request_body: @promotion_code_request_body,
    responses: [created: {"Promotion code", "application/json", @open_object}]
  )

  def create_promotion_code(conn, params) do
    with {:ok, code} <-
           CreateFinancePromotionCode.call(param_id(params), body_params(conn, params)) do
      conn
      |> put_status(:created)
      |> json(%{promotion_code: code})
    end
  end

  operation(:referral_programs,
    summary: "List referral programs",
    responses: [ok: {"Referral programs", "application/json", @list_response}]
  )

  def referral_programs(conn, _params) do
    with {:ok, payload} <- ListFinanceReferralPrograms.call() do
      json(conn, payload)
    end
  end

  operation(:create_referral_program,
    summary: "Create a referral program",
    request_body: @referral_program_request_body,
    responses: [created: {"Referral program", "application/json", @open_object}]
  )

  def create_referral_program(conn, params) do
    with {:ok, program} <-
           CreateFinanceReferralProgram.call(body_params(conn, params)) do
      conn
      |> put_status(:created)
      |> json(%{referral_program: program})
    end
  end

  operation(:update_referral_program,
    summary: "Update a referral program",
    parameters: [@id_parameter],
    request_body: @update_referral_program_request_body,
    responses: [ok: {"Referral program", "application/json", @open_object}]
  )

  def update_referral_program(conn, params) do
    with {:ok, program} <-
           UpdateFinanceReferralProgram.call(param_id(params), body_params(conn, params)) do
      json(conn, %{referral_program: program})
    end
  end

  operation(:referrals,
    summary: "List referral events",
    responses: [ok: {"Referral events", "application/json", @list_response}]
  )

  def referrals(conn, _params) do
    with {:ok, payload} <- ListFinanceReferrals.call() do
      json(conn, payload)
    end
  end

  operation(:create_referral,
    summary: "Create a referral event",
    request_body: @referral_event_request_body,
    responses: [created: {"Referral event", "application/json", @open_object}]
  )

  def create_referral(conn, params) do
    with {:ok, event} <- CreateFinanceReferralEvent.call(body_params(conn, params)) do
      conn
      |> put_status(:created)
      |> json(%{referral_event: event})
    end
  end

  operation(:update_referral_status,
    summary: "Update referral event status",
    parameters: [@id_parameter],
    request_body: @request_body,
    responses: [ok: {"Referral event", "application/json", @open_object}]
  )

  def update_referral_status(conn, params) do
    status = body_params(conn, params)["status"] || params["status"]

    with {:ok, event} <- UpdateFinanceReferralStatus.call(param_id(params), status) do
      json(conn, %{referral_event: event})
    end
  end

  operation(:referral_rewards,
    summary: "List referral rewards",
    responses: [ok: {"Referral rewards", "application/json", @list_response}]
  )

  def referral_rewards(conn, _params) do
    with {:ok, payload} <- ListFinanceReferralRewards.call() do
      json(conn, payload)
    end
  end

  operation(:update_referral_reward_status,
    summary: "Update referral reward status",
    parameters: [@id_parameter],
    request_body: @request_body,
    responses: [ok: {"Referral reward", "application/json", @open_object}]
  )

  def update_referral_reward_status(conn, params) do
    status = body_params(conn, params)["status"] || params["status"]

    with {:ok, reward} <- UpdateFinanceReferralRewardStatus.call(param_id(params), status) do
      json(conn, %{referral_reward: reward})
    end
  end

  operation(:create_referral_reward,
    summary: "Create a referral reward for a referral event",
    parameters: [@id_parameter],
    request_body: @referral_reward_request_body,
    responses: [created: {"Referral reward", "application/json", @open_object}]
  )

  def create_referral_reward(conn, params) do
    with {:ok, reward} <-
           CreateFinanceReferralReward.call(param_id(params), body_params(conn, params)) do
      conn
      |> put_status(:created)
      |> json(%{referral_reward: reward})
    end
  end

  operation(:invoice_upload_url,
    summary: "Generate a presigned upload URL for an invoice file",
    parameters: [@id_parameter],
    request_body: @invoice_upload_url_request_body,
    responses: [ok: {"Upload URL", "application/json", @open_object}]
  )

  def invoice_upload_url(conn, params) do
    invoice_id = param_id(params)
    body = body_params(conn, params)
    file_name = body["file_name"] || body[:file_name] || ""
    content_type = body["content_type"] || body[:content_type] || "application/octet-stream"
    ext = Path.extname(file_name)
    key = "invoices/#{invoice_id}/#{Ecto.UUID.generate()}#{ext}"

    with {:ok, upload_url} <- MinioStorage.presigned_upload_url(key),
         {:ok, invoice} <- MilosTraining.Finance.get_invoice(invoice_id),
         updated_params <-
           Map.merge(invoice.params || %{}, %{"file_key" => key, "file_name" => file_name}),
         {:ok, _} <- MilosTraining.Finance.update_invoice_params(invoice_id, updated_params) do
      json(conn, %{upload_url: upload_url, file_key: key, content_type: content_type})
    end
  end

  operation(:invoice_download_url,
    summary: "Generate a presigned download URL for an invoice file",
    parameters: [@id_parameter],
    responses: [ok: {"Download URL", "application/json", @open_object}]
  )

  def invoice_download_url(conn, params) do
    invoice_id = param_id(params)

    with {:ok, invoice} <- MilosTraining.Finance.get_invoice(invoice_id),
         file_key when is_binary(file_key) <- (invoice.params || %{})["file_key"],
         {:ok, download_url} <- MinioStorage.presigned_download_url(file_key) do
      file_name = (invoice.params || %{})["file_name"] || Path.basename(file_key)
      json(conn, %{download_url: download_url, file_name: file_name})
    else
      nil -> {:error, :not_found}
      err -> err
    end
  end

  defp param_id(params), do: params["id"] || params[:id]

  defp body_params(conn, params),
    do:
      Map.drop(conn.body_params || params, [
        "id",
        :id,
        "payment_id",
        :payment_id,
        "invoice_id",
        :invoice_id,
        "credit_ledger_entry_id",
        :credit_ledger_entry_id
      ])

  defp current_user_id(conn) do
    conn
    |> Guardian.Plug.current_resource()
    |> Map.fetch!(:id)
  end
end
