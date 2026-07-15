defmodule MilosTrainingWeb.NotificationController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug

  alias MilosTraining.Application.{
    DeletePushSubscription,
    GetNotifications,
    GetPushNotificationConfig,
    GetPushSubscriptionStatus,
    MarkNotificationClicked,
    MarkNotificationRead,
    MarkNotificationsRead,
    SavePushSubscription
  }

  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Notifications"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true]
       when action in [
              :index,
              :create_push_subscription,
              :delete_push_subscription,
              :push_subscription_status,
              :mark_clicked,
              :mark_read
            ]

  @notification_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      user_id: %Schema{type: :string, format: :uuid},
      type: %Schema{type: :string},
      payload: %Schema{type: :object, additionalProperties: true},
      read_at: %Schema{type: :string, format: :"date-time", nullable: true},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :user_id, :type, :payload, :inserted_at]
  }

  @push_keys_schema %Schema{
    type: :object,
    properties: %{
      p256dh: %Schema{type: :string},
      auth: %Schema{type: :string}
    },
    required: [:p256dh, :auth]
  }

  @push_subscription_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      user_id: %Schema{type: :string, format: :uuid},
      endpoint: %Schema{type: :string},
      expiration_time: %Schema{type: :string, format: :"date-time", nullable: true},
      keys: @push_keys_schema,
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :user_id, :endpoint, :keys, :inserted_at, :updated_at]
  }

  @push_subscription_params_schema %Schema{
    type: :object,
    properties: %{
      endpoint: %Schema{type: :string},
      expiration_time: %Schema{type: :string, format: :"date-time", nullable: true},
      keys: @push_keys_schema
    },
    required: [:endpoint, :keys]
  }

  @push_subscription_status_schema %Schema{
    type: :object,
    properties: %{
      registered: %Schema{type: :boolean},
      subscription: %Schema{allOf: [@push_subscription_schema], nullable: true}
    },
    required: [:registered, :subscription]
  }

  @push_subscription_endpoint_param %Parameter{
    name: :endpoint,
    in: :query,
    description: "Subscription endpoint",
    required: true,
    schema: %Schema{type: :string}
  }

  operation(:index,
    summary: "List notifications for the current user",
    parameters: [
      %Parameter{
        name: :limit,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 50}
      },
      %Parameter{
        name: :cursor,
        in: :query,
        required: false,
        schema: %Schema{type: :string}
      }
    ],
    responses: [
      ok:
        {"Notifications", "application/json",
         %Schema{
           type: :object,
           properties: %{
             notifications: %Schema{type: :array, items: @notification_schema},
             unread_count: %Schema{type: :integer},
             next_cursor: %Schema{type: :string, nullable: true}
           },
           required: [:notifications, :unread_count, :next_cursor]
         }}
    ]
  )

  operation(:mark_all_read,
    summary: "Mark all notifications as read for the current user",
    responses: [
      ok:
        {"Read count", "application/json",
         %Schema{
           type: :object,
           properties: %{marked_count: %Schema{type: :integer}},
           required: [:marked_count]
         }}
    ]
  )

  operation(:mark_read,
    summary: "Mark a single notification as read for the current user",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        description: "Notification ID",
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [
      ok:
        {"Read result", "application/json",
         %Schema{
           type: :object,
           properties: %{read: %Schema{type: :boolean}},
           required: [:read]
         }},
      not_found:
        {"Not found", "application/json",
         %Schema{
           type: :object,
           properties: %{error: %Schema{type: :string}},
           required: [:error]
         }}
    ]
  )

  operation(:mark_clicked,
    summary: "Record a notification click and mark it read for the current user",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        description: "Notification ID",
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: %RequestBody{
      required: false,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              url: %Schema{type: :string, nullable: true},
              metadata: %Schema{type: :object, additionalProperties: true}
            }
          }
        }
      }
    },
    responses: [
      ok:
        {"Click result", "application/json",
         %Schema{
           type: :object,
           properties: %{clicked: %Schema{type: :boolean}, read: %Schema{type: :boolean}},
           required: [:clicked, :read]
         }}
    ]
  )

  operation(:push_config,
    summary: "Get Web Push configuration for the current user",
    responses: [
      ok:
        {"Push config", "application/json",
         %Schema{
           type: :object,
           properties: %{
             enabled: %Schema{type: :boolean},
             vapid_public_key: %Schema{type: :string, nullable: true}
           },
           required: [:enabled, :vapid_public_key]
         }}
    ]
  )

  operation(:create_push_subscription,
    summary: "Save or update a push subscription for the current user",
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: @push_subscription_params_schema}}
    },
    responses: [
      ok:
        {"Push subscription", "application/json",
         %Schema{
           type: :object,
           properties: %{subscription: @push_subscription_schema},
           required: [:subscription]
         }},
      created:
        {"Push subscription", "application/json",
         %Schema{
           type: :object,
           properties: %{subscription: @push_subscription_schema},
           required: [:subscription]
         }}
    ]
  )

  operation(:delete_push_subscription,
    summary: "Delete a push subscription for the current user",
    parameters: [@push_subscription_endpoint_param],
    request_body: nil,
    responses: [
      ok:
        {"Delete result", "application/json",
         %Schema{
           type: :object,
           properties: %{deleted: %Schema{type: :boolean}},
           required: [:deleted]
         }}
    ]
  )

  operation(:push_subscription_status,
    summary: "Inspect whether a push subscription endpoint is persisted for the current user",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{endpoint: %Schema{type: :string}},
            required: [:endpoint]
          }
        }
      }
    },
    responses: [
      ok: {"Push subscription status", "application/json", @push_subscription_status_schema}
    ]
  )

  def index(conn, params) do
    actor = GuardianPlug.current_resource(conn)

    with {:ok, payload} <- GetNotifications.call(actor.id, params) do
      json(conn, payload)
    end
  end

  def mark_all_read(conn, _params) do
    actor = GuardianPlug.current_resource(conn)
    marked_count = MarkNotificationsRead.call(actor.id)
    json(conn, %{marked_count: marked_count})
  end

  def mark_read(conn, %{id: notification_id}) do
    actor = GuardianPlug.current_resource(conn)

    with :ok <- MarkNotificationRead.call(actor.id, notification_id) do
      json(conn, %{read: true})
    end
  end

  def mark_clicked(conn, %{id: notification_id} = params) do
    actor = GuardianPlug.current_resource(conn)
    body = normalize_body_params(conn, params)

    with {:ok, _click_event} <- MarkNotificationClicked.call(actor.id, notification_id, body) do
      json(conn, %{clicked: true, read: true})
    end
  end

  def push_config(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> json(GetPushNotificationConfig.call())
  end

  def create_push_subscription(conn, params) do
    actor = GuardianPlug.current_resource(conn)
    body = normalize_body_params(conn, params)

    with {:ok, subscription, status} <- SavePushSubscription.call(actor.id, body) do
      conn
      |> put_status(if(status == :created, do: :created, else: :ok))
      |> json(%{subscription: subscription})
    end
  end

  def push_subscription_status(conn, params) do
    actor = GuardianPlug.current_resource(conn)
    body = normalize_body_params(conn, params)
    endpoint = Map.get(body, "endpoint") || Map.get(body, :endpoint)

    json(conn, GetPushSubscriptionStatus.call(actor.id, endpoint))
  end

  def delete_push_subscription(conn, params) do
    actor = GuardianPlug.current_resource(conn)
    body = normalize_body_params(conn, params)
    endpoint = Map.get(body, "endpoint") || Map.get(body, :endpoint)
    deleted = DeletePushSubscription.call(actor.id, endpoint)
    json(conn, %{deleted: deleted})
  end

  defp normalize_body_params(conn, params) do
    case conn.body_params do
      %{} = body_params when map_size(body_params) > 0 -> body_params
      _ -> Map.get(params, "body") || Map.get(params, :body) || params
    end
  end
end
