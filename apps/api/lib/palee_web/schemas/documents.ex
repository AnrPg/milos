defmodule PaleeWeb.Schemas.Documents do
  @moduledoc "OpenAPI schemas of the Documents context (ADR-252)."

  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  @uuid %Schema{type: :string, format: :uuid}
  @nullable_uuid %Schema{type: :string, format: :uuid, nullable: true}
  @date %Schema{type: :string, format: :date}
  @time %Schema{type: :string, format: :"date-time"}
  @nullable_time %Schema{type: :string, format: :"date-time", nullable: true}
  @hash %Schema{type: :string, pattern: "^[0-9a-f]{64}$"}
  @kinds ["waiver", "terms", "privacy", "health_certificate", "other"]
  @requirements ["mandatory", "optional"]
  @languages ["el", "en", "de", "fr", "es", "it", "ru", "pt-PT", "nl", "bg", "ar", "he"]
  @health_statuses ["missing", "valid", "expiring", "expired"]
  @content_types ["application/pdf", "image/jpeg", "image/png", "image/webp"]

  def uuid, do: @uuid

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  def one(key, schema), do: %Schema{type: :object, properties: %{key => schema}, required: [key]}

  def path_id(name \\ :id), do: %Parameter{name: name, in: :path, required: true, schema: @uuid}

  def query(name, schema), do: %Parameter{name: name, in: :query, required: false, schema: schema}

  def paging do
    [
      query(:limit, %Schema{type: :integer, minimum: 1, maximum: 200}),
      query(:offset, %Schema{type: :integer, minimum: 0})
    ]
  end

  # ── Documents ───────────────────────────────────────────────────────────

  def version do
    %Schema{
      type: :object,
      properties: %{
        id: @uuid,
        template_id: @uuid,
        number: %Schema{type: :integer, minimum: 1},
        title: %Schema{type: :string},
        language: %Schema{type: :string},
        change_kind: %Schema{type: :string, enum: ["major", "minor"]},
        content_hash: @hash,
        published_by_id: @nullable_uuid,
        published_at: @time,
        body: %Schema{type: :string, description: "Only when one version is read"}
      },
      required: [
        :change_kind,
        :content_hash,
        :id,
        :language,
        :number,
        :published_at,
        :published_by_id,
        :template_id,
        :title
      ]
    }
  end

  def template do
    %Schema{
      type: :object,
      properties: %{
        id: @uuid,
        kind: %Schema{type: :string, enum: @kinds},
        title: %Schema{type: :string},
        requirement: %Schema{type: :string, enum: @requirements},
        status: %Schema{type: :string, enum: ["active", "archived"]},
        current_version_id: @nullable_uuid,
        current_version_number: %Schema{type: :integer, minimum: 0},
        required_version_number: %Schema{
          type: :integer,
          minimum: 0,
          description: "The latest major version; older signatures no longer count"
        },
        archived_at: @nullable_time,
        inserted_at: @time,
        updated_at: @time,
        versions: %Schema{type: :array, items: version()}
      },
      required: [
        :archived_at,
        :current_version_id,
        :current_version_number,
        :id,
        :inserted_at,
        :kind,
        :required_version_number,
        :requirement,
        :status,
        :title,
        :updated_at
      ]
    }
  end

  def templates,
    do: %Schema{
      type: :object,
      properties: %{templates: %Schema{type: :array, items: template()}},
      required: [:templates]
    }

  def template_detail do
    %Schema{
      type: :object,
      properties: %{
        template: template(),
        current_version: %Schema{version() | nullable: true}
      },
      required: [:current_version, :template]
    }
  end

  def published do
    %Schema{
      type: :object,
      properties: %{template: template(), version: version()},
      required: [:template, :version]
    }
  end

  def starters do
    starter = %Schema{
      type: :object,
      properties: %{
        kind: %Schema{type: :string, enum: @kinds},
        language: %Schema{type: :string},
        title: %Schema{type: :string},
        body: %Schema{type: :string},
        requirement: %Schema{type: :string, enum: @requirements},
        draft: %Schema{type: :boolean},
        legal_review_required: %Schema{type: :boolean}
      },
      required: [:body, :draft, :kind, :language, :legal_review_required, :requirement, :title]
    }

    %Schema{
      type: :object,
      properties: %{starters: %Schema{type: :array, items: starter}},
      required: [:starters]
    }
  end

  def template_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        kind: %Schema{type: :string, enum: @kinds},
        title: %Schema{type: :string, minLength: 1, maxLength: 200},
        requirement: %Schema{type: :string, enum: @requirements},
        body: %Schema{type: :string, minLength: 1, maxLength: 100_000},
        language: %Schema{type: :string, enum: @languages}
      },
      required: [:body, :kind, :title]
    }
  end

  def version_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        title: %Schema{type: :string, minLength: 1, maxLength: 200},
        body: %Schema{type: :string, minLength: 1, maxLength: 100_000},
        language: %Schema{type: :string, enum: @languages},
        change_kind: %Schema{
          type: :string,
          enum: ["major", "minor"],
          description: "major (default): everyone signs again; minor: earlier signatures count"
        }
      },
      required: [:body]
    }
  end

  def requirement_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{requirement: %Schema{type: :string, enum: @requirements}},
      required: [:requirement]
    }
  end

  def outstanding do
    client = %Schema{
      type: :object,
      properties: %{
        user_id: @uuid,
        display_name: %Schema{type: :string, nullable: true},
        handle: %Schema{type: :string, nullable: true},
        status: %Schema{type: :string, enum: ["unsigned", "resign_required"]}
      },
      required: [:display_name, :handle, :status, :user_id]
    }

    row = %Schema{
      type: :object,
      properties: %{
        template_id: @uuid,
        signed: %Schema{type: :integer, description: "Clients whose signature counts"},
        outstanding: %Schema{type: :integer},
        clients: %Schema{type: :array, items: client, description: "Clients who have not signed"}
      },
      required: [:clients, :outstanding, :signed, :template_id]
    }

    %Schema{
      type: :object,
      properties: %{templates: %Schema{type: :array, items: row}},
      required: [:templates]
    }
  end

  # ── Requests and signatures ─────────────────────────────────────────────

  def request do
    %Schema{
      type: :object,
      properties: %{
        id: @uuid,
        template_id: @uuid,
        user_id: @uuid,
        batch_id: @nullable_uuid,
        audience: %Schema{type: :string, enum: ["person", "all_clients", "role", "package"]},
        status: %Schema{type: :string, enum: ["pending", "signed", "cancelled"]},
        requested_by_id: @nullable_uuid,
        requested_at: @time,
        signature_id: @nullable_uuid,
        closed_at: @nullable_time
      },
      required: [
        :audience,
        :batch_id,
        :closed_at,
        :id,
        :requested_at,
        :requested_by_id,
        :signature_id,
        :status,
        :template_id,
        :user_id
      ]
    }
  end

  def request_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        audience: %Schema{type: :string, enum: ["person", "all_clients", "role", "package"]},
        user_id: @uuid,
        role: %Schema{type: :string, enum: ["member", "athlete"]},
        package_id: @uuid
      },
      required: [:audience]
    }
  end

  def request_result do
    %Schema{
      type: :object,
      properties: %{
        batch_id: @uuid,
        audience: %Schema{type: :string},
        recipients: %Schema{type: :integer},
        created: %Schema{type: :integer},
        skipped: %Schema{type: :integer, description: "Already signed or already asked"},
        requests: %Schema{type: :array, items: request()}
      },
      required: [:audience, :batch_id, :created, :recipients, :requests, :skipped]
    }
  end

  def request_page do
    %Schema{
      type: :object,
      properties: %{
        requests: %Schema{type: :array, items: request()},
        total: %Schema{type: :integer}
      },
      required: [:requests, :total]
    }
  end

  def signature do
    %Schema{
      type: :object,
      properties: %{
        id: @uuid,
        template_id: @uuid,
        version_id: @uuid,
        version_number: %Schema{type: :integer},
        request_id: @nullable_uuid,
        user_id: @uuid,
        signed_at: @time,
        level: %Schema{type: :string, enum: ["simple", "advanced", "qualified"]},
        provider: %Schema{type: :string},
        content_hash: @hash,
        typed_name: %Schema{type: :string, nullable: true},
        ip_address: %Schema{type: :string, nullable: true},
        user_agent: %Schema{type: :string, nullable: true},
        evidence_hash: @hash,
        evidence_sha256: @hash,
        evidence_byte_size: %Schema{type: :integer},
        has_drawn_signature: %Schema{type: :boolean},
        account: %Schema{
          type: :object,
          description: "The signer's account at signing time",
          additionalProperties: true
        }
      },
      required: [
        :account,
        :content_hash,
        :evidence_byte_size,
        :evidence_hash,
        :evidence_sha256,
        :has_drawn_signature,
        :id,
        :ip_address,
        :level,
        :provider,
        :request_id,
        :signed_at,
        :template_id,
        :typed_name,
        :user_agent,
        :user_id,
        :version_id,
        :version_number
      ]
    }
  end

  def signature_page do
    %Schema{
      type: :object,
      properties: %{
        signatures: %Schema{type: :array, items: signature()},
        total: %Schema{type: :integer}
      },
      required: [:signatures, :total]
    }
  end

  def evidence_link do
    %Schema{
      type: :object,
      properties: %{
        url: %Schema{type: :string, description: "Short-lived link to the PDF certificate"},
        sha256: @hash,
        byte_size: %Schema{type: :integer}
      },
      required: [:byte_size, :sha256, :url]
    }
  end

  def sign_body do
    point = %Schema{type: :array, items: %Schema{type: :number}, minItems: 2, maxItems: 2}

    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        version_id: %Schema{type: :string, format: :uuid, description: "The version read"},
        agreed: %Schema{type: :boolean, description: "I have read and accept the text"},
        typed_name: %Schema{type: :string, minLength: 2, maxLength: 120},
        drawn_signature: %Schema{
          type: :object,
          additionalProperties: false,
          properties: %{
            width: %Schema{type: :integer, minimum: 10, maximum: 2000},
            height: %Schema{type: :integer, minimum: 10, maximum: 2000},
            strokes: %Schema{
              type: :array,
              minItems: 1,
              maxItems: 100,
              items: %Schema{type: :array, minItems: 1, items: point}
            }
          },
          required: [:height, :strokes, :width]
        }
      },
      required: [:agreed, :version_id]
    }
  end

  # ── A client's documents ────────────────────────────────────────────────

  def item do
    %Schema{
      type: :object,
      properties: %{
        template_id: @uuid,
        kind: %Schema{type: :string, enum: @kinds},
        title: %Schema{type: :string},
        requirement: %Schema{type: :string, enum: @requirements},
        current_version_id: @nullable_uuid,
        current_version_number: %Schema{type: :integer},
        status: %Schema{type: :string, enum: ["signed", "unsigned", "resign_required"]},
        outstanding: %Schema{type: :boolean, description: "Mandatory and not signed"},
        requested: %Schema{type: :boolean, description: "Staff asked for it"},
        signature: %Schema{
          type: :object,
          nullable: true,
          properties: %{
            id: @uuid,
            version_number: %Schema{type: :integer},
            signed_at: @time,
            content_hash: @hash
          },
          required: [:content_hash, :id, :signed_at, :version_number]
        }
      },
      required: [
        :current_version_id,
        :current_version_number,
        :kind,
        :outstanding,
        :requested,
        :requirement,
        :signature,
        :status,
        :template_id,
        :title
      ]
    }
  end

  def certificate do
    %Schema{
      type: :object,
      properties: %{
        id: @uuid,
        user_id: @uuid,
        issued_on: @date,
        expires_on: %Schema{
          type: :string,
          format: :date,
          description: "The first day it is no longer valid"
        },
        content_type: %Schema{type: :string, enum: @content_types},
        byte_size: %Schema{type: :integer},
        uploaded_by_id: @nullable_uuid,
        inserted_at: @time
      },
      required: [
        :byte_size,
        :content_type,
        :expires_on,
        :id,
        :inserted_at,
        :issued_on,
        :uploaded_by_id,
        :user_id
      ]
    }
  end

  def my_overview do
    %Schema{
      type: :object,
      properties: %{
        documents: %Schema{type: :array, items: item()},
        outstanding: %Schema{type: :integer},
        health_certificate: %Schema{
          type: :object,
          properties: %{
            required: %Schema{type: :boolean},
            status: %Schema{type: :string, enum: @health_statuses},
            certificate: %Schema{certificate() | nullable: true}
          },
          required: [:certificate, :required, :status]
        }
      },
      required: [:documents, :health_certificate, :outstanding]
    }
  end

  def my_document do
    %Schema{
      type: :object,
      properties: %{
        template: template(),
        version: version(),
        status: %Schema{type: :string, nullable: true}
      },
      required: [:status, :template, :version]
    }
  end

  def member do
    %Schema{
      type: :object,
      properties: %{
        user_id: @uuid,
        documents: %Schema{type: :array, items: item()},
        outstanding: %Schema{type: :integer},
        signatures: %Schema{type: :array, items: signature()},
        health_certificate_status: %Schema{type: :string, enum: @health_statuses}
      },
      required: [:documents, :health_certificate_status, :outstanding, :signatures, :user_id]
    }
  end

  # ── Health certificates ─────────────────────────────────────────────────

  def health_rows do
    row = %Schema{
      type: :object,
      properties: %{
        user_id: @uuid,
        display_name: %Schema{type: :string, nullable: true},
        handle: %Schema{type: :string, nullable: true},
        status: %Schema{type: :string, enum: @health_statuses},
        certificate: %Schema{
          certificate()
          | nullable: true,
            description: "Only for staff who manage health certificates"
        }
      },
      required: [:certificate, :display_name, :handle, :status, :user_id]
    }

    %Schema{
      type: :object,
      properties: %{
        health_certificates: %Schema{type: :array, items: row},
        required: %Schema{type: :boolean},
        full_access: %Schema{type: :boolean}
      },
      required: [:full_access, :health_certificates, :required]
    }
  end

  def client_certificates do
    %Schema{
      type: :object,
      properties: %{
        user_id: @uuid,
        health_certificates: %Schema{type: :array, items: certificate()}
      },
      required: [:health_certificates, :user_id]
    }
  end

  def upload_request_body(staff?) do
    properties = %{content_type: %Schema{type: :string, enum: @content_types}}

    if staff?,
      do: %Schema{
        type: :object,
        additionalProperties: false,
        properties: Map.put(properties, :user_id, @uuid),
        required: [:content_type, :user_id]
      },
      else: %Schema{
        type: :object,
        additionalProperties: false,
        properties: properties,
        required: [:content_type]
      }
  end

  def upload do
    %Schema{
      type: :object,
      properties: %{
        upload_url: %Schema{type: :string},
        method: %Schema{type: :string, enum: ["PUT"]},
        required_headers: %Schema{
          type: :object,
          additionalProperties: %Schema{type: :string}
        },
        file_key: %Schema{type: :string},
        content_type: %Schema{type: :string, enum: @content_types},
        max_bytes: %Schema{type: :integer}
      },
      required: [:content_type, :file_key, :max_bytes, :method, :required_headers, :upload_url]
    }
  end

  def upload_complete_body(staff?) do
    properties = %{
      file_key: %Schema{type: :string, maxLength: 500},
      content_type: %Schema{type: :string, enum: @content_types},
      issued_on: @date,
      expires_on: %Schema{
        type: :string,
        format: :date,
        description: "Default: the issue date plus the box's validity (12 months)"
      }
    }

    required = [:content_type, :file_key, :issued_on]

    if staff?,
      do: %Schema{
        type: :object,
        additionalProperties: false,
        properties: Map.put(properties, :user_id, @uuid),
        required: Enum.sort([:user_id | required])
      },
      else: %Schema{
        type: :object,
        additionalProperties: false,
        properties: properties,
        required: required
      }
  end

  def file_link do
    %Schema{
      type: :object,
      properties: %{
        url: %Schema{type: :string, description: "Short-lived link; the look is audited"},
        content_type: %Schema{type: :string}
      },
      required: [:content_type, :url]
    }
  end

  # ── Settings and audit ──────────────────────────────────────────────────

  def settings do
    %Schema{
      type: :object,
      properties: %{
        block_booking_on_unsigned: %Schema{type: :boolean},
        health_certificate_required: %Schema{type: :boolean},
        block_booking_on_health_certificate: %Schema{type: :boolean},
        health_certificate_validity_months: %Schema{type: :integer, minimum: 1, maximum: 24},
        health_certificate_reminder_days: %Schema{type: :integer, minimum: 0, maximum: 90}
      },
      required: [
        :block_booking_on_health_certificate,
        :block_booking_on_unsigned,
        :health_certificate_reminder_days,
        :health_certificate_required,
        :health_certificate_validity_months
      ]
    }
  end

  def settings_body, do: %Schema{settings() | required: nil, additionalProperties: false}

  def events do
    event = %Schema{
      type: :object,
      properties: %{
        id: @uuid,
        action: %Schema{type: :string},
        actor_id: @nullable_uuid,
        subject_type: %Schema{type: :string},
        subject_id: @nullable_uuid,
        subject_user_id: @nullable_uuid,
        details: %Schema{type: :object, additionalProperties: true},
        occurred_at: @time
      },
      required: [
        :action,
        :actor_id,
        :details,
        :id,
        :occurred_at,
        :subject_id,
        :subject_type,
        :subject_user_id
      ]
    }

    %Schema{
      type: :object,
      properties: %{events: %Schema{type: :array, items: event}, total: %Schema{type: :integer}},
      required: [:events, :total]
    }
  end
end
