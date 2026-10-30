defmodule PaleeWeb.Schemas.FiscalCompliance do
  @moduledoc "OpenAPI schemas of Peppol e-invoicing (ADR-250) and TSE/RKSV signing (ADR-251)."

  alias OpenApiSpex.Schema

  @uuid %Schema{type: :string, format: :uuid}
  @time %Schema{type: :string, format: :"date-time"}
  @environments ["sandbox", "test", "production"]

  defp nullable(%Schema{} = schema), do: %Schema{schema | nullable: true}

  # ── Peppol ──────────────────────────────────────────────────────────────

  @einvoice_statuses [
    "pending",
    "sending",
    "submitted",
    "delivered",
    "rejected",
    "failed",
    "uncertain"
  ]

  def einvoice_statuses, do: @einvoice_statuses

  def einvoice do
    %Schema{
      type: :object,
      description: "The document's Peppol submission (ADR-250).",
      properties: %{
        id: @uuid,
        document_id: @uuid,
        network: %Schema{type: :string, enum: ["peppol"]},
        status: %Schema{type: :string, enum: @einvoice_statuses},
        attempts: %Schema{type: :integer},
        polls: %Schema{type: :integer},
        next_attempt_at: nullable(@time),
        environment: %Schema{type: :string, nullable: true},
        recipient_scheme: %Schema{type: :string},
        recipient_identifier: %Schema{type: :string},
        provider_submission_id: %Schema{type: :string, nullable: true},
        submitted_at: nullable(@time),
        delivered_at: nullable(@time),
        last_error_code: %Schema{type: :string, nullable: true},
        last_error_message: %Schema{type: :string, nullable: true},
        inserted_at: @time,
        updated_at: @time
      },
      required: [
        :attempts,
        :document_id,
        :id,
        :network,
        :recipient_identifier,
        :recipient_scheme,
        :status
      ]
    }
  end

  def attempt do
    %Schema{
      type: :object,
      properties: %{
        id: @uuid,
        attempt: %Schema{type: :integer},
        operation: %Schema{type: :string},
        environment: %Schema{type: :string},
        outcome: %Schema{type: :string},
        response_status: %Schema{type: :integer, nullable: true},
        error: %Schema{type: :string, nullable: true},
        duration_ms: %Schema{type: :integer, nullable: true},
        started_at: @time
      },
      required: [:attempt, :environment, :id, :operation, :outcome, :started_at]
    }
  end

  def einvoice_detail do
    %Schema{
      einvoice()
      | properties:
          Map.put(einvoice().properties, :attempts_log, %Schema{type: :array, items: attempt()}),
        required: Enum.sort([:attempts_log | einvoice().required])
    }
  end

  def einvoice_page do
    %Schema{
      type: :object,
      properties: %{
        submissions: %Schema{type: :array, items: einvoice()},
        total: %Schema{type: :integer},
        counts: %Schema{type: :object, additionalProperties: %Schema{type: :integer}}
      },
      required: [:counts, :submissions, :total]
    }
  end

  def peppol_connection do
    PaleeWeb.Schemas.FiscalConnections.with_check(%Schema{
      type: :object,
      description:
        "The Peppol connection; the API key, secret and webhook token are never returned. " <>
          "`storecove` is a retired provider of old connections: they show as invalid " <>
          "(`provider_retired`) until reconnected.",
      properties: %{
        network: %Schema{type: :string, enum: ["peppol"]},
        provider: %Schema{type: :string, enum: ["sandbox", "fiskaly", "storecove"]},
        environment: %Schema{type: :string, enum: @environments},
        peppol_id: %Schema{type: :string, example: "0208:0123456749"},
        legal_entity_id: %Schema{
          type: :string,
          nullable: true,
          description: "fiskaly: the business's E-INVOICE System id."
        },
        has_api_key: %Schema{type: :boolean},
        has_api_secret: %Schema{type: :boolean},
        credentials_source: %Schema{
          type: :string,
          enum: ["own", "till_connection", "none"],
          description:
            "`till_connection`: no key of its own, the fiskaly till connection's is used."
        },
        has_webhook_token: %Schema{type: :boolean},
        status: %Schema{type: :string, enum: ["active", "invalid"]},
        updated_at: @time
      },
      required: [
        :credentials_source,
        :environment,
        :has_api_key,
        :has_api_secret,
        :has_webhook_token,
        :network,
        :peppol_id,
        :provider,
        :status,
        :updated_by_platform
      ]
    })
  end

  def peppol_connection_status do
    %Schema{
      type: :object,
      properties: %{
        connection: nullable(peppol_connection()),
        environments: %Schema{type: :array, items: %Schema{type: :string, enum: @environments}}
      },
      required: [:connection, :environments]
    }
  end

  def peppol_connection_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        environment: %Schema{type: :string, enum: @environments},
        peppol_id: %Schema{
          type: :string,
          nullable: true,
          maxLength: 60,
          description: "`scheme:identifier`; defaults to `0208:` + the enterprise number."
        },
        provider: %Schema{
          type: :string,
          enum: ["fiskaly"],
          description: "Access point outside the sandbox; defaults to `fiskaly`."
        },
        legal_entity_id: %Schema{
          type: :string,
          nullable: true,
          maxLength: 40,
          description: "fiskaly: the business's E-INVOICE System id."
        },
        api_key: %Schema{
          type: :string,
          nullable: true,
          maxLength: 500,
          description:
            "Leave out to keep the saved key, or (fiskaly) to use the fiskaly till " <>
              "connection's key and secret."
        },
        api_secret: %Schema{
          type: :string,
          nullable: true,
          maxLength: 500,
          description: "Leave out to keep the saved secret."
        },
        rotate_webhook_token: %Schema{type: :boolean}
      },
      required: [:environment]
    }
  end

  # ── TSE / RKSV ──────────────────────────────────────────────────────────

  @signature_statuses [
    "pending",
    "sending",
    "signed",
    "uncertain",
    "device_failed",
    "rejected",
    "failed"
  ]

  def signature_statuses, do: @signature_statuses

  def print_line do
    %Schema{
      type: :object,
      properties: %{
        label: %Schema{type: :string},
        value: %Schema{type: :string, nullable: true}
      },
      required: [:label]
    }
  end

  def till_signature do
    %Schema{
      type: :object,
      description:
        "A receipt's TSE/RKSV signature (ADR-251); `print` is what the receipt prints.",
      properties: %{
        id: @uuid,
        document_id: nullable(@uuid),
        device: %Schema{type: :string, enum: ["tse", "rksv", "sign_fr"]},
        kind: %Schema{
          type: :string,
          enum: ["receipt", "start", "null", "monthly", "yearly", "closing"]
        },
        period: %Schema{type: :string, format: :date, nullable: true},
        status: %Schema{type: :string, enum: @signature_statuses},
        attempts: %Schema{type: :integer},
        next_attempt_at: nullable(@time),
        environment: %Schema{type: :string, nullable: true},
        transaction_number: %Schema{type: :integer, nullable: true},
        signature_counter: %Schema{type: :integer, nullable: true},
        signature_value: %Schema{type: :string, nullable: true},
        signature_algorithm: %Schema{type: :string, nullable: true},
        time_format: %Schema{type: :string, nullable: true},
        started_at_device: nullable(@time),
        finished_at_device: nullable(@time),
        unit_serial: %Schema{type: :string, nullable: true},
        register_serial: %Schema{type: :string, nullable: true},
        receipt_number: %Schema{type: :string, nullable: true},
        qr_code_data: %Schema{type: :string, nullable: true},
        signed_at: nullable(@time),
        failed_at: nullable(@time),
        last_error_code: %Schema{type: :string, nullable: true},
        last_error_message: %Schema{type: :string, nullable: true},
        print: %Schema{type: :array, items: print_line()},
        inserted_at: @time,
        updated_at: @time
      },
      required: [:attempts, :device, :id, :kind, :print, :status]
    }
  end

  def till_signature_detail do
    %Schema{
      till_signature()
      | properties:
          Map.put(till_signature().properties, :attempts_log, %Schema{
            type: :array,
            items: attempt()
          }),
        required: Enum.sort([:attempts_log | till_signature().required])
    }
  end

  def till_signature_page do
    %Schema{
      type: :object,
      properties: %{
        signatures: %Schema{type: :array, items: till_signature()},
        total: %Schema{type: :integer},
        counts: %Schema{type: :object, additionalProperties: %Schema{type: :integer}}
      },
      required: [:counts, :signatures, :total]
    }
  end

  def till_connection do
    PaleeWeb.Schemas.FiscalConnections.with_check(%Schema{
      type: :object,
      description:
        "The TSE (DE), RKSV (AT) or SIGN FR (FR) connection; key, secret and admin PIN are " <>
          "never returned.",
      properties: %{
        device: %Schema{type: :string, enum: ["tse", "rksv", "sign_fr"]},
        provider: %Schema{type: :string, enum: ["sandbox", "fiskaly"]},
        environment: %Schema{type: :string, enum: @environments},
        unit_id: @uuid,
        register_id: @uuid,
        unit_serial: %Schema{type: :string, nullable: true},
        register_serial: %Schema{type: :string, nullable: true},
        public_key: %Schema{type: :string, nullable: true},
        provisioned_at: nullable(@time),
        has_api_key: %Schema{type: :boolean},
        has_api_secret: %Schema{type: :boolean},
        status: %Schema{type: :string, enum: ["provisioning", "active", "invalid"]},
        updated_at: @time
      },
      required: [
        :device,
        :environment,
        :has_api_key,
        :has_api_secret,
        :provider,
        :register_id,
        :status,
        :unit_id,
        :updated_by_platform
      ]
    })
  end

  def till_connection_status do
    %Schema{
      type: :object,
      properties: %{
        connection: nullable(till_connection()),
        environments: %Schema{type: :array, items: %Schema{type: :string, enum: @environments}}
      },
      required: [:connection, :environments]
    }
  end

  def till_connection_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        environment: %Schema{type: :string, enum: @environments},
        api_key: %Schema{type: :string, nullable: true, maxLength: 200},
        api_secret: %Schema{type: :string, nullable: true, maxLength: 200},
        reprovision: %Schema{
          type: :boolean,
          description:
            "Create a new TSS/client (DE), signature unit/cash register (AT) or " <>
              "taxpayer/location/System (SIGN FR)."
        }
      },
      required: [:environment]
    }
  end
end
