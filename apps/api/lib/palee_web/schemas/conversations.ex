defmodule PaleeWeb.Schemas.Conversations do
  @moduledoc "OpenAPI schemas for person-to-person conversations (ADR-193 §3)."

  alias OpenApiSpex.Schema
  alias PaleeWeb.Schemas.Community

  @uuid %Schema{type: :string, format: :uuid}
  @datetime %Schema{type: :string, format: :"date-time"}

  def uuid, do: @uuid
  def body(schema), do: Community.body(schema)

  def folder, do: %Schema{type: :string, enum: ~w(inbox requests)}

  def message do
    %Schema{
      title: "PersonMessage",
      type: :object,
      properties: %{
        id: @uuid,
        conversation_id: @uuid,
        author_id: @uuid,
        body: %Schema{type: :string},
        mine: %Schema{type: :boolean},
        client_operation_id: %Schema{type: :string, format: :uuid, nullable: true},
        created_at: @datetime
      },
      required: [:author_id, :body, :conversation_id, :created_at, :id, :mine]
    }
  end

  def conversation do
    person = %Schema{
      title: "ConversationPerson",
      type: :object,
      properties: %{
        id: @uuid,
        nickname: %Schema{type: :string, nullable: true},
        handle: %Schema{type: :string, nullable: true},
        avatar_url: %Schema{type: :string, nullable: true}
      },
      required: [:id]
    }

    %Schema{
      title: "PersonConversation",
      type: :object,
      properties: %{
        id: @uuid,
        person: person,
        folder: folder(),
        buddy: %Schema{type: :boolean, description: "You and they follow each other"},
        started_by_me: %Schema{type: :boolean},
        unread: %Schema{type: :boolean},
        last_message_at: %Schema{allOf: [@datetime], nullable: true},
        last_message: %Schema{allOf: [message()], nullable: true}
      },
      required: [:buddy, :folder, :id, :person, :started_by_me, :unread]
    }
  end

  def conversation_response do
    %Schema{
      title: "PersonConversationResponse",
      type: :object,
      properties: %{conversation: conversation()},
      required: [:conversation]
    }
  end

  def conversation_page do
    %Schema{
      title: "PersonConversationPage",
      type: :object,
      properties: %{
        conversations: %Schema{type: :array, items: conversation()},
        next_cursor: %Schema{type: :string, nullable: true}
      },
      required: [:conversations]
    }
  end

  def message_page do
    %Schema{
      title: "PersonMessagePage",
      type: :object,
      properties: %{
        messages: %Schema{type: :array, items: message()},
        next_cursor: %Schema{type: :string, nullable: true}
      },
      required: [:messages]
    }
  end

  def message_response do
    %Schema{
      title: "PersonMessageResponse",
      type: :object,
      properties: %{message: message()},
      required: [:message]
    }
  end

  def open_request do
    %Schema{
      title: "PersonConversationOpenRequest",
      type: :object,
      properties: %{person_id: @uuid},
      required: [:person_id]
    }
  end

  def message_request do
    %Schema{
      title: "PersonMessageRequest",
      type: :object,
      properties: %{
        body: %Schema{type: :string, minLength: 1, maxLength: 4000},
        client_operation_id: %Schema{type: :string, format: :uuid}
      },
      required: [:body]
    }
  end

  def unread_count_response do
    %Schema{
      title: "PersonConversationUnreadCount",
      type: :object,
      properties: %{inbox: %Schema{type: :integer}, requests: %Schema{type: :integer}},
      required: [:inbox, :requests]
    }
  end
end
