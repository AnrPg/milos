defmodule PaleeWeb.Schemas.CrossProvider do
  @moduledoc """
  OpenAPI shapes of one journal across providers (ADR-162): Box ▾
  providers and the merged «Σήμερα», account-level history, Πρόοδος and
  Vault, «Οι coach μου» audiences and the whole-journal export.
  """

  alias OpenApiSpex.Schema

  @uuid %Schema{type: :string, format: :uuid}
  @nullable_uuid %Schema{type: :string, format: :uuid, nullable: true}
  @datetime %Schema{type: :string, format: :"date-time"}
  @nullable_datetime %Schema{type: :string, format: :"date-time", nullable: true}
  @nullable_string %Schema{type: :string, nullable: true}
  @provider_kind %Schema{type: :string, enum: ["gym", "coach"]}
  @source_tokens %Schema{
    type: :array,
    items: %Schema{type: :string},
    description: "Provider ids, `freeform`, `device`."
  }

  def source do
    %Schema{
      title: "EntrySource",
      type: :object,
      description: "Where an entry came from; `former` once the membership there ended.",
      required: [:kind, :organization_id, :name, :former],
      properties: %{
        kind: %Schema{type: :string, enum: ["organization", "freeform", "device"]},
        organization_id: @nullable_uuid,
        name: @nullable_string,
        former: %Schema{type: :boolean}
      }
    }
  end

  @doc "A coach of a provider, as «Οι coach μου» names one."
  def coach_ref do
    %Schema{
      title: "CoachRef",
      type: :object,
      required: [:organization_id, :user_id],
      properties: %{organization_id: @uuid, user_id: @uuid},
      additionalProperties: false
    }
  end

  def audience do
    %Schema{
      title: "EntryAudience",
      type: :object,
      nullable: true,
      description:
        "Coaches a coach rung on this entry reaches (and their providers); `custom` when the entry has its own audience.",
      required: [:custom, :organization_ids, :coaches],
      properties: %{
        custom: %Schema{type: :boolean},
        organization_ids: %Schema{type: :array, items: @uuid},
        coaches: %Schema{type: :array, items: coach_ref()}
      }
    }
  end

  @next %Schema{
    type: :object,
    nullable: true,
    required: [:kind, :at, :id],
    properties: %{
      kind: %Schema{type: :string, enum: ["class", "appointment"]},
      at: @datetime,
      title: @nullable_string,
      id: @uuid
    }
  }

  def providers_response do
    %Schema{
      title: "MyProviders",
      type: :object,
      required: [:selected_organization_id, :providers, :former],
      properties: %{
        selected_organization_id: @nullable_uuid,
        providers: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            required: [:organization_id, :name, :slug, :kind, :selected, :unread_messages],
            properties: %{
              organization_id: @uuid,
              name: %Schema{type: :string},
              slug: %Schema{type: :string},
              kind: @provider_kind,
              logo_url: @nullable_string,
              primary_color: @nullable_string,
              roles: %Schema{type: :array, items: %Schema{type: :string}},
              selected: %Schema{type: :boolean},
              next: @next,
              unread_messages: %Schema{type: :integer},
              partial: %Schema{type: :boolean, description: "Live facts could not be read."}
            }
          }
        },
        former: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            required: [:organization_id, :name, :kind],
            properties: %{
              organization_id: @uuid,
              name: %Schema{type: :string},
              slug: %Schema{type: :string},
              kind: @provider_kind,
              logo_url: @nullable_string,
              primary_color: @nullable_string,
              ended_at: @nullable_datetime
            }
          }
        }
      }
    }
  end

  def select_request do
    %Schema{
      title: "SelectProviderRequest",
      type: :object,
      required: [:organization_id],
      properties: %{organization_id: @uuid},
      additionalProperties: false
    }
  end

  def today_response do
    %Schema{
      title: "MyToday",
      type: :object,
      required: [:date, :timezone, :items, :partial, :failed_organization_ids],
      properties: %{
        date: %Schema{type: :string, format: :date},
        timezone: %Schema{type: :string},
        partial: %Schema{type: :boolean},
        failed_organization_ids: %Schema{type: :array, items: @uuid},
        items: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            required: [:kind, :id, :at, :source, :target],
            properties: %{
              kind: %Schema{type: :string, enum: ["class", "appointment", "program", "wod"]},
              id: @uuid,
              at: %Schema{
                type: :string,
                format: :"date-time",
                nullable: true,
                description: "Null for untimed items (programme of the day, WOD), listed first."
              },
              title: @nullable_string,
              status: @nullable_string,
              source: source(),
              target: %Schema{
                type: :object,
                required: [:organization_id, :slug],
                properties: %{organization_id: @uuid, slug: %Schema{type: :string}}
              }
            }
          }
        }
      }
    }
  end

  @score %Schema{
    type: :object,
    properties: %{
      section_id: @nullable_string,
      section_name: @nullable_string,
      value: %Schema{nullable: true},
      unit: @nullable_string
    }
  }

  def history_page do
    %Schema{
      title: "AccountHistoryPage",
      type: :object,
      required: [:kind, :total, :offset, :next_offset, :entries],
      properties: %{
        kind: %Schema{type: :string, enum: ["workouts", "classes"]},
        total: %Schema{type: :integer},
        offset: %Schema{type: :integer},
        next_offset: %Schema{type: :integer, nullable: true},
        entries: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            required: [:id, :occurred_at, :source],
            properties: %{
              id: @uuid,
              occurred_at: @nullable_datetime,
              source: source(),
              execution_source: @nullable_string,
              workout: %Schema{
                type: :object,
                nullable: true,
                properties: %{id: @nullable_uuid, title: @nullable_string, type: @nullable_string}
              },
              class: %Schema{
                type: :object,
                nullable: true,
                properties: %{
                  name: @nullable_string,
                  type_name: @nullable_string,
                  duration_minutes: %Schema{type: :integer, nullable: true},
                  attendance: @nullable_string
                }
              },
              performance: %Schema{
                type: :object,
                nullable: true,
                properties: %{
                  execution_id: @uuid,
                  status: %Schema{type: :string},
                  started_at: @nullable_datetime,
                  completed_at: @nullable_datetime,
                  elapsed_ms: %Schema{type: :integer, nullable: true},
                  scale_level_slug: @nullable_string,
                  scores: %Schema{type: :array, items: @score}
                }
              }
            }
          }
        }
      }
    }
  end

  def progress_response do
    %Schema{
      title: "AccountProgress",
      type: :object,
      required: [
        :totals,
        :weekly,
        :days,
        :consistency,
        :sources,
        :score_history,
        :pr_timeline,
        :by_source,
        :available_sources,
        :filter,
        :active_filter_count
      ],
      properties: %{
        totals: %Schema{type: :object, additionalProperties: true},
        weekly: %Schema{type: :array, items: %Schema{type: :object, additionalProperties: true}},
        days: %Schema{
          type: :array,
          description:
            "Sessions per day with training over the range's weeks, oldest first (ADR-194)",
          items: %Schema{
            type: :object,
            properties: %{
              date: %Schema{type: :string, format: :date},
              sessions: %Schema{type: :integer}
            },
            required: [:date, :sessions]
          }
        },
        consistency: %Schema{type: :object, additionalProperties: true},
        sources: %Schema{
          type: :object,
          additionalProperties: %Schema{type: :integer},
          description: "Sessions by how they started (class_booking, assigned, …)."
        },
        score_history: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              workout_id: %Schema{
                type: :string,
                description: "The canonical workout identity (benchmark:…, library:…, title:…)."
              },
              workout_title: @nullable_string,
              section_id: @nullable_string,
              section_name: @nullable_string,
              unit: @nullable_string,
              points: %Schema{
                type: :array,
                items: %Schema{
                  type: :object,
                  properties: %{
                    execution_id: @uuid,
                    completed_on: %Schema{type: :string, format: :date},
                    value: %Schema{nullable: true},
                    source: source()
                  }
                }
              }
            }
          }
        },
        pr_timeline: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            additionalProperties: true,
            properties: %{source: source()}
          }
        },
        by_source: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            required: [:source, :sessions],
            properties: %{source: source(), sessions: %Schema{type: :integer}}
          }
        },
        available_sources: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description:
            "Source tokens (organization id, `freeform`, `device`) the person has any completed " <>
              "workout from, whatever the filter or range: the «Πηγή» chip shows only with two " <>
              "or more (ADR-285)."
        },
        filter: %Schema{type: :object, additionalProperties: true},
        active_filter_count: %Schema{type: :integer}
      }
    }
  end

  def vault_response do
    %Schema{
      title: "AccountVault",
      type: :object,
      required: [:groups, :filter, :active_filter_count],
      properties: %{
        filter: %Schema{type: :object, additionalProperties: true},
        active_filter_count: %Schema{type: :integer},
        groups: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            required: [:identity, :title, :attempt_count, :last_at, :sources, :attempts],
            properties: %{
              identity: %Schema{type: :string},
              benchmark: @nullable_string,
              title: @nullable_string,
              workout_type: @nullable_string,
              attempt_count: %Schema{type: :integer},
              last_at: @datetime,
              sources: %Schema{type: :array, items: source()},
              attempts: %Schema{
                type: :array,
                items: %Schema{
                  type: :object,
                  required: [:kind, :id, :organization_id, :master_workout_id, :at, :source],
                  properties: %{
                    kind: %Schema{type: :string, enum: ["execution", "training_log"]},
                    id: @uuid,
                    organization_id: %Schema{
                      type: :string,
                      format: :uuid,
                      nullable: true,
                      description:
                        "Provider the attempt belongs to (null for a freeform or device entry); «Ξανά» switches to it first."
                    },
                    master_workout_id: %Schema{
                      type: :string,
                      format: :uuid,
                      nullable: true,
                      description: "Workout to repeat, when the attempt has one."
                    },
                    title: @nullable_string,
                    type: @nullable_string,
                    at: @datetime,
                    on: %Schema{type: :string, format: :date},
                    tz: @nullable_string,
                    source: source(),
                    scale_level_slug: @nullable_string,
                    duration_seconds: %Schema{type: :integer, nullable: true},
                    scores: %Schema{type: :array, items: @score}
                  }
                }
              }
            }
          }
        }
      }
    }
  end

  def coach_audience_response do
    %Schema{
      title: "CoachAudience",
      type: :object,
      required: [:organization_ids, :coaches, :providers],
      properties: %{
        organization_ids: %Schema{
          type: :array,
          items: @uuid,
          description: "Providers with at least one coach «Οι coach μου» means by default."
        },
        coaches: %Schema{
          type: :array,
          items: coach_ref(),
          description: "The coaches «Οι coach μου» means by default."
        },
        providers: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            required: [:organization_id, :name, :kind, :included, :coaches],
            properties: %{
              organization_id: @uuid,
              name: %Schema{type: :string},
              kind: @provider_kind,
              included: %Schema{type: :boolean},
              coaches: %Schema{
                type: :array,
                items: %Schema{
                  type: :object,
                  required: [:user_id, :name, :included],
                  properties: %{
                    user_id: @uuid,
                    name: @nullable_string,
                    avatar_url: @nullable_string,
                    included: %Schema{type: :boolean}
                  }
                }
              }
            }
          }
        }
      }
    }
  end

  def coach_audience_request do
    %Schema{
      title: "CoachAudienceRequest",
      type: :object,
      description: "The coaches «Οι coach μου» means; a provider id means all its coaches.",
      properties: %{
        organization_ids: %Schema{type: :array, items: @uuid},
        coaches: %Schema{type: :array, items: coach_ref()}
      },
      additionalProperties: false
    }
  end

  def entry_audience_request do
    %Schema{
      title: "EntryAudienceRequest",
      type: :object,
      description:
        "Who this entry is shared with: coaches, and providers meaning all their coaches. Both null resets to the default.",
      properties: %{
        organization_ids: %Schema{type: :array, items: @uuid, nullable: true},
        coaches: %Schema{type: :array, items: coach_ref(), nullable: true}
      },
      additionalProperties: false
    }
  end

  def entry_audience_response do
    %Schema{
      title: "EntryAudienceResponse",
      type: :object,
      required: [:kind, :id, :audience],
      properties: %{kind: %Schema{type: :string}, id: @uuid, audience: audience()}
    }
  end

  def export do
    %Schema{
      title: "JournalExport",
      type: :object,
      required: [:id, :status, :requested_at, :files],
      properties: %{
        id: @uuid,
        status: %Schema{type: :string, enum: ["pending", "ready", "failed", "expired"]},
        entry_count: %Schema{type: :integer, nullable: true},
        requested_at: @datetime,
        completed_at: @nullable_datetime,
        expires_at: @nullable_datetime,
        files: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            required: [:name, :content_type, :download_url],
            properties: %{
              name: %Schema{type: :string},
              content_type: %Schema{type: :string},
              bytes: %Schema{type: :integer, nullable: true},
              download_url: %Schema{
                type: :string,
                nullable: true,
                description: "Short-lived; ask again for a fresh one."
              }
            }
          }
        }
      }
    }
  end

  def export_response do
    %Schema{
      title: "JournalExportResponse",
      type: :object,
      required: [:export],
      properties: %{export: export()}
    }
  end

  def exports_response do
    %Schema{
      title: "JournalExports",
      type: :object,
      required: [:exports],
      properties: %{exports: %Schema{type: :array, items: export()}}
    }
  end

  def source_tokens, do: @source_tokens
end
