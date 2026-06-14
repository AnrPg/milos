defmodule MilosTrainingWeb.MessagingController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Messaging
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Messaging"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true] when action in [:create_thread, :send_message]

  @thread_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      context_type: %Schema{type: :string, enum: ["direct", "assignment", "class_slot"]},
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
            last_read_message_id: %Schema{type: :string, format: :uuid, nullable: true}
          }
        }
      }
    }
  }

  @message_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      thread_id: %Schema{type: :string, format: :uuid},
      sender_id: %Schema{type: :string, format: :uuid},
      body: %Schema{type: :string},
      message_type: %Schema{type: :string, enum: ["chat", "coaching_note", "system"]},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    }
  }

  operation(:create_thread,
    summary: "Create or get an existing thread",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              context_type: %Schema{
                type: :string,
                enum: ["direct", "assignment", "class_slot"],
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
         %Schema{type: :object, properties: %{thread: @thread_schema}}}
    ]
  )

  operation(:list_threads,
    summary: "List threads for the current user",
    parameters: [
      %Parameter{
        name: :context_type,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: ["direct", "assignment", "class_slot"]}
      }
    ],
    responses: [
      ok:
        {"Threads list", "application/json",
         %Schema{
           type: :object,
           properties: %{threads: %Schema{type: :array, items: @thread_schema}}
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
         %Schema{type: :object, properties: %{thread: @thread_schema}}},
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
        schema: %Schema{type: :integer, default: 50}
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
        {"Messages", "application/json",
         %Schema{
           type: :object,
           properties: %{messages: %Schema{type: :array, items: @message_schema}}
         }},
      forbidden: {"Forbidden", "application/json", %Schema{type: :object}}
    ]
  )

  operation(:send_message,
    summary: "Send a message in a thread",
    parameters: [
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
                enum: ["chat", "coaching_note"],
                default: "chat"
              }
            },
            required: [:body]
          }
        }
      }
    },
    responses: [
      created:
        {"Message created", "application/json",
         %Schema{type: :object, properties: %{message: @message_schema}}},
      not_found: {"Not found", "application/json", %Schema{type: :object}},
      forbidden: {"Forbidden", "application/json", %Schema{type: :object}}
    ]
  )

  operation(:mark_read,
    summary: "Mark a message as read in a thread",
    parameters: [
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
      ok: {"Marked read", "application/json", %Schema{type: :object}},
      not_found: {"Not found", "application/json", %Schema{type: :object}},
      forbidden: {"Forbidden", "application/json", %Schema{type: :object}}
    ]
  )

  def create_thread(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    raw_context_type = bp(conn, "context_type") || "direct"
    context_type = parse_context_type(raw_context_type)

    params =
      %{context_type: context_type, actor_id: user.id}
      |> maybe_put(:participant_id, bp(conn, "participant_id"))
      |> maybe_put(:context_id, bp(conn, "context_id"))

    with {:ok, thread} <- Messaging.get_or_create_thread(params) do
      json(conn, %{thread: serialize_thread(thread)})
    end
  end

  def list_threads(conn, params) do
    user = Guardian.Plug.current_resource(conn)
    context_type = parse_context_type(params["context_type"])

    threads = Messaging.list_threads_for_user(user.id, context_type)
    json(conn, %{threads: Enum.map(threads, &serialize_thread/1)})
  end

  def show_thread(conn, params) do
    user = Guardian.Plug.current_resource(conn)
    thread_id = params["id"] || params[:id]

    with {:ok, thread} <- Messaging.get_thread(thread_id, user.id) do
      json(conn, %{thread: serialize_thread(thread)})
    end
  end

  def list_messages(conn, params) do
    user = Guardian.Plug.current_resource(conn)
    thread_id = params["id"] || params[:id]

    list_params =
      %{actor_id: user.id}
      |> maybe_put(:limit, parse_int(params["limit"] || params[:limit]))
      |> maybe_put(:before_id, params["before_id"] || params[:before_id])

    with {:ok, messages} <- Messaging.list_messages(thread_id, list_params) do
      json(conn, %{messages: Enum.map(messages, &serialize_message/1)})
    end
  end

  def send_message(conn, params) do
    user = Guardian.Plug.current_resource(conn)
    thread_id = params["id"] || params[:id]
    message_type = parse_message_type(bp(conn, "message_type") || "chat")

    with {:ok, message} <-
           Messaging.send_message(%{
             thread_id: thread_id,
             sender_id: user.id,
             body: bp(conn, "body"),
             message_type: message_type
           }) do
      conn
      |> put_status(:created)
      |> json(%{message: serialize_message(message)})
    end
  end

  def mark_read(conn, params) do
    user = Guardian.Plug.current_resource(conn)
    thread_id = params["id"] || params[:id]
    message_id = bp(conn, "message_id")

    with :ok <- Messaging.mark_read(thread_id, user.id, message_id) do
      json(conn, %{})
    end
  end

  defp serialize_thread(thread) do
    %{
      id: thread.id,
      context_type: thread.context_type,
      context_id: thread.context_id,
      created_by_id: thread.created_by_id,
      inserted_at: thread.inserted_at,
      participants: Enum.map(thread.participants || [], &serialize_participant/1)
    }
  end

  defp serialize_participant(p) do
    %{id: p.id, user_id: p.user_id, last_read_message_id: p.last_read_message_id}
  end

  defp serialize_message(message) do
    %{
      id: message.id,
      thread_id: message.thread_id,
      sender_id: message.sender_id,
      body: message.body,
      message_type: message.message_type,
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
  defp parse_context_type(_), do: nil

  defp parse_message_type("coaching_note"), do: :coaching_note
  defp parse_message_type("system"), do: :system
  defp parse_message_type(_), do: :chat

  defp parse_int(nil), do: nil
  defp parse_int(str) when is_binary(str), do: String.to_integer(str)
  defp parse_int(int) when is_integer(int), do: int
end
