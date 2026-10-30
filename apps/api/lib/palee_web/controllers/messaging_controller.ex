defmodule PaleeWeb.MessagingController do
  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.{
    BoxInbox,
    CountUnreadMessagingThreads,
    GetMessagingThread,
    GetOrCreateMessagingThread,
    ListMessagingMessages,
    ListMessagingThreads,
    MarkMessagingThreadRead
  }

  alias Palee.Application.SendMessage, as: SendMessageUseCase
  alias PaleeWeb.ParamExtractor
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  @topics ~w(booking payment membership facility training)

  action_fallback PaleeWeb.FallbackController

  def action(conn, _) do
    case conn.assigns[:tenant_context] do
      nil ->
        apply(__MODULE__, action_name(conn), [conn, conn.params])

      context ->
        Palee.Messaging.with_tenant_context(context, fn ->
          apply(__MODULE__, action_name(conn), [conn, conn.params])
        end)
    end
  end

  tags(["Messaging"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true]
       when action in [:create_thread, :send_message, :mark_read, :bring_coach]

  @thread_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      context_type: %Schema{type: :string, enum: ["direct", "assignment", "class_slot", "box"]},
      context_id: %Schema{type: :string, format: :uuid, nullable: true},
      created_by_id: %Schema{type: :string, format: :uuid},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      participants: %Schema{
        type: :array,
        items: %Schema{
          type: :object,
          properties: %{
            id: %Schema{type: :string, format: :uuid},
            user_id: %Schema{type: :string, format: :uuid},
            nickname: %Schema{type: :string, nullable: true},
            last_read_message_id: %Schema{type: :string, format: :uuid, nullable: true},
            joined_as: %Schema{
              type: :string,
              enum: ["member", "staff", "coach"],
              nullable: true,
              description: "ADR-282: why someone is in a box thread"
            }
          },
          required: [:id, :user_id, :nickname, :last_read_message_id]
        }
      },
      last_message: %Schema{
        type: :object,
        nullable: true,
        properties: %{
          id: %Schema{type: :string, format: :uuid},
          sender_id: %Schema{type: :string, format: :uuid},
          body: %Schema{type: :string},
          message_type: %Schema{type: :string},
          topic: %Schema{type: :string, nullable: true},
          inserted_at: %Schema{type: :string, format: :"date-time"}
        },
        required: [:id, :sender_id, :body, :message_type, :topic, :inserted_at]
      },
      box_person: %Schema{
        type: :object,
        nullable: true,
        description: "ADR-282: in a box thread, whether the person is a newcomer and blocked",
        properties: %{newcomer: %Schema{type: :boolean}, blocked: %Schema{type: :boolean}},
        required: [:blocked, :newcomer]
      }
    },
    required: [:id, :context_type, :context_id, :created_by_id, :inserted_at, :participants]
  }

  @block_schema %Schema{
    type: :object,
    properties: %{blocked: %Schema{type: :boolean}},
    required: [:blocked]
  }

  @coach_candidate_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      nickname: %Schema{type: :string, nullable: true},
      avatar_url: %Schema{type: :string, nullable: true},
      coaches_person: %Schema{type: :boolean},
      in_thread: %Schema{type: :boolean}
    },
    required: [:avatar_url, :coaches_person, :id, :in_thread, :nickname]
  }

  @organization_slug_parameter %Parameter{
    name: :organization_slug,
    in: :path,
    required: false,
    schema: %Schema{type: :string}
  }

  @message_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      thread_id: %Schema{type: :string, format: :uuid},
      sender_id: %Schema{type: :string, format: :uuid},
      body: %Schema{type: :string},
      message_type: %Schema{
        type: :string,
        enum: ["chat", "coaching_message", "box_message", "system"]
      },
      topic: %Schema{type: :string, enum: @topics, nullable: true},
      client_operation_id: %Schema{type: :string, format: :uuid, nullable: true},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [
      :id,
      :thread_id,
      :sender_id,
      :body,
      :message_type,
      :client_operation_id,
      :inserted_at
    ]
  }

  operation(:create_thread,
    summary: "Create or get an existing thread",
    parameters: [@organization_slug_parameter],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              context_type: %Schema{
                type: :string,
                enum: ["direct", "assignment", "class_slot", "box"],
                default: "direct"
              },
              participant_id: %Schema{type: :string, format: :uuid},
              context_id: %Schema{type: :string, format: :uuid}
            }
          }
        }
      }
    },
    responses: [
      ok:
        {"Thread", "application/json",
         %Schema{type: :object, properties: %{thread: @thread_schema}, required: [:thread]}}
    ]
  )

  operation(:list_threads,
    summary: "List threads for the current user",
    parameters: [
      %Parameter{
        name: :context_type,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: ["direct", "assignment", "class_slot", "box"]}
      }
    ],
    responses: [
      ok:
        {"Threads list", "application/json",
         %Schema{
           type: :object,
           properties: %{threads: %Schema{type: :array, items: @thread_schema}},
           required: [:threads]
         }}
    ]
  )

  operation(:show_thread,
    summary: "Get a single thread",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [
      ok:
        {"Thread", "application/json",
         %Schema{type: :object, properties: %{thread: @thread_schema}, required: [:thread]}},
      not_found: {"Not found", "application/json", %Schema{type: :object}},
      forbidden: {"Forbidden", "application/json", %Schema{type: :object}}
    ]
  )

  operation(:list_messages,
    summary: "List messages in a thread",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      },
      %Parameter{
        name: :limit,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, default: 50, minimum: 1, maximum: 100}
      },
      %Parameter{
        name: :before_id,
        in: :query,
        required: false,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [
      ok:
        {"Chat messages", "application/json",
         %Schema{
           type: :object,
           properties: %{messages: %Schema{type: :array, items: @message_schema}},
           required: [:messages]
         }},
      forbidden: {"Forbidden", "application/json", %Schema{type: :object}}
    ]
  )

  operation(:send_message,
    summary: "Send a message in a thread",
    parameters: [
      @organization_slug_parameter,
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              body: %Schema{type: :string, minLength: 1, maxLength: 5000},
              message_type: %Schema{
                type: :string,
                enum: ["chat", "coaching_message", "box_message"],
                default: "chat",
                description:
                  "A coaching message needs an active coaching relationship; in the gym's " <>
                    "thread with a member, staff always write a message from the box."
              },
              topic: %Schema{
                type: :string,
                enum: @topics,
                description: "What a message from the box is about."
              },
              client_operation_id: %Schema{type: :string, format: :uuid}
            },
            required: [:body]
          }
        }
      }
    },
    responses: [
      created:
        {"Message created", "application/json",
         %Schema{type: :object, properties: %{message: @message_schema}, required: [:message]}},
      not_found: {"Not found", "application/json", %Schema{type: :object}},
      forbidden: {"Forbidden", "application/json", %Schema{type: :object}}
    ]
  )

  operation(:unread_count,
    summary: "Count unread threads for the current user",
    responses: [
      ok:
        {"Unread count", "application/json",
         %Schema{
           type: :object,
           properties: %{unread_count: %Schema{type: :integer}},
           required: [:unread_count]
         }}
    ]
  )

  operation(:mark_read,
    summary: "Mark a message as read in a thread",
    parameters: [
      @organization_slug_parameter,
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{message_id: %Schema{type: :string, format: :uuid}},
            required: [:message_id]
          }
        }
      }
    },
    responses: [
      ok:
        {"Marked read", "application/json",
         %Schema{
           type: :object,
           properties: %{
             read: %Schema{type: :boolean},
             message_id: %Schema{type: :string, format: :uuid}
           },
           required: [:read, :message_id]
         }},
      not_found: {"Not found", "application/json", %Schema{type: :object}},
      forbidden: {"Forbidden", "application/json", %Schema{type: :object}}
    ]
  )

  def unread_count(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    count = CountUnreadMessagingThreads.call(user.id)
    json(conn, %{unread_count: count})
  end

  def create_thread(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    raw_context_type = bp(conn, "context_type") || "direct"
    context_type = parse_context_type(raw_context_type)

    params =
      %{context_type: context_type, actor_id: user.id}
      |> maybe_put(:participant_id, bp(conn, "participant_id"))
      |> maybe_put(:context_id, bp(conn, "context_id"))

    with {:ok, thread} <-
           GetOrCreateMessagingThread.call(conn.assigns[:tenant_context] || %{}, user, params) do
      json(conn, %{thread: serialize_thread(thread)})
    end
  end

  def list_threads(conn, params) do
    user = Guardian.Plug.current_resource(conn)
    context_type = parse_context_type(params["context_type"])

    threads = ListMessagingThreads.call(conn.assigns[:tenant_context] || %{}, user.id, context_type)

    json(conn, %{threads: Enum.map(threads, &serialize_thread/1)})
  end

  def show_thread(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, thread_id} <- ParamExtractor.fetch(params, "id"),
         :ok <- authorize_box(conn, user, thread_id),
         {:ok, thread} <- GetMessagingThread.call(thread_id, user.id) do
      json(conn, %{thread: serialize_thread(thread)})
    end
  end

  def list_messages(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, thread_id} <- ParamExtractor.fetch(params, "id"),
         :ok <- authorize_box(conn, user, thread_id) do
      list_params =
        %{actor_id: user.id}
        |> maybe_put(:limit, ParamExtractor.get(params, "limit"))
        |> maybe_put(:before_id, ParamExtractor.get(params, "before_id"))

      with {:ok, messages} <- ListMessagingMessages.call(thread_id, list_params) do
        json(conn, %{messages: Enum.map(messages, &serialize_message/1)})
      end
    end
  end

  def send_message(conn, params) do
    user = Guardian.Plug.current_resource(conn)
    message_type = parse_message_type(bp(conn, "message_type") || "chat")

    with {:ok, thread_id} <- ParamExtractor.fetch(params, "id"),
         :ok <- authorize_box(conn, user, thread_id),
         {:ok, message} <-
           SendMessageUseCase.call(user, %{
             thread_id: thread_id,
             sender_id: user.id,
             body: bp(conn, "body"),
             message_type: message_type,
             topic: bp(conn, "topic"),
             client_operation_id: bp(conn, "client_operation_id")
           }) do
      conn
      |> put_status(:created)
      |> json(%{message: serialize_message(message)})
    end
  end

  def mark_read(conn, params) do
    user = Guardian.Plug.current_resource(conn)
    message_id = bp(conn, "message_id")

    with {:ok, thread_id} <- ParamExtractor.fetch(params, "id"),
         :ok <- authorize_box(conn, user, thread_id),
         {:ok, result} <- MarkMessagingThreadRead.call(thread_id, user.id, message_id) do
      json(conn, result)
    end
  end

  operation(:coach_candidates,
    summary: "The coaches the box's inbox may bring into a box thread (ADR-282)",
    parameters: [
      @organization_slug_parameter,
      %Parameter{name: :id, in: :path, required: true, schema: %Schema{type: :string}}
    ],
    responses: [
      ok:
        {"Coaches", "application/json",
         %Schema{
           type: :object,
           properties: %{coaches: %Schema{type: :array, items: @coach_candidate_schema}},
           required: [:coaches]
         }},
      forbidden: {"Not in the box's inbox", "application/json", %Schema{type: :object}}
    ]
  )

  def coach_candidates(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, thread_id} <- ParamExtractor.fetch(params, "id"),
         {:ok, coaches} <- BoxInbox.coach_candidates(tenant_context(conn), user.id, thread_id) do
      json(conn, %{coaches: coaches})
    end
  end

  operation(:bring_coach,
    summary: "«Φέρε τον coach»: bring a coach of the box into a box thread (ADR-282)",
    parameters: [
      @organization_slug_parameter,
      %Parameter{name: :id, in: :path, required: true, schema: %Schema{type: :string}}
    ],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{user_id: %Schema{type: :string, format: :uuid}},
            required: [:user_id]
          }
        }
      }
    },
    responses: [
      ok:
        {"Thread", "application/json",
         %Schema{type: :object, properties: %{thread: @thread_schema}, required: [:thread]}},
      forbidden: {"Not in the box's inbox", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"Not a coach of the box", "application/json", %Schema{type: :object}}
    ]
  )

  def bring_coach(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, thread_id} <- ParamExtractor.fetch(params, "id"),
         {:ok, thread} <-
           BoxInbox.bring_coach(tenant_context(conn), user.id, thread_id, bp(conn, "user_id")) do
      json(conn, %{thread: serialize_thread(thread)})
    end
  end

  operation(:block_sender,
    summary: "The box stops hearing from a newcomer who wrote to it (ADR-282)",
    parameters: [
      @organization_slug_parameter,
      %Parameter{name: :id, in: :path, required: true, schema: %Schema{type: :string}}
    ],
    responses: [
      ok: {"Blocked", "application/json", @block_schema},
      forbidden: {"Not in the box's inbox", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"A client of the box", "application/json", %Schema{type: :object}}
    ]
  )

  def block_sender(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, thread_id} <- ParamExtractor.fetch(params, "id"),
         {:ok, _thread} <- BoxInbox.block(tenant_context(conn), user.id, thread_id) do
      json(conn, %{blocked: true})
    end
  end

  operation(:unblock_sender,
    summary: "The box hears from the person again (ADR-282)",
    parameters: [
      @organization_slug_parameter,
      %Parameter{name: :id, in: :path, required: true, schema: %Schema{type: :string}}
    ],
    responses: [
      ok: {"Unblocked", "application/json", @block_schema},
      forbidden: {"Not in the box's inbox", "application/json", %Schema{type: :object}}
    ]
  )

  def unblock_sender(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, thread_id} <- ParamExtractor.fetch(params, "id"),
         {:ok, _thread} <- BoxInbox.unblock(tenant_context(conn), user.id, thread_id) do
      json(conn, %{blocked: false})
    end
  end

  defp tenant_context(conn), do: conn.assigns[:tenant_context] || %{}

  # ADR-282: box threads are read by role, so the inbox check runs first.
  defp authorize_box(conn, user, thread_id) do
    case conn.assigns[:tenant_context] do
      nil -> :ok
      context -> BoxInbox.authorize(context, user.id, thread_id)
    end
  end

  defp serialize_thread(thread) do
    %{
      id: thread.id,
      context_type: thread.context_type,
      context_id: thread.context_id,
      created_by_id: thread.created_by_id,
      inserted_at: thread.inserted_at,
      participants: Enum.map(thread.participants || [], &serialize_participant/1),
      last_message: last_message(thread),
      box_person: Map.get(thread, :box_person)
    }
  end

  defp last_message(%{messages: [%{} = message | _rest]}),
    do:
      Map.take(message, [:id, :sender_id, :body, :message_type, :topic, :inserted_at])

  defp last_message(_thread), do: nil

  defp serialize_participant(p) do
    %{
      id: p.id,
      user_id: p.user_id,
      nickname: Map.get(p, :nickname),
      last_read_message_id: p.last_read_message_id,
      joined_as: Map.get(p, :joined_as)
    }
  end

  defp serialize_message(message) do
    %{
      id: message.id,
      thread_id: message.thread_id,
      sender_id: message.sender_id,
      body: message.body,
      message_type: message.message_type,
      client_operation_id: message.client_operation_id,
      subject_kind: message.subject_kind,
      subject_id: message.subject_id,
      topic: message.topic,
      inserted_at: message.inserted_at
    }
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp bp(conn, key) when is_binary(key) do
    Map.get(conn.body_params, key) || Map.get(conn.body_params, String.to_atom(key))
  end

  defp parse_context_type(nil), do: nil
  defp parse_context_type("direct"), do: :direct
  defp parse_context_type("assignment"), do: :assignment
  defp parse_context_type("class_slot"), do: :class_slot
  defp parse_context_type("box"), do: :box
  defp parse_context_type(_), do: nil

  defp parse_message_type("coaching_message"), do: :coaching_message
  defp parse_message_type("box_message"), do: :box_message
  defp parse_message_type("system"), do: :system
  defp parse_message_type(_), do: :chat
end
