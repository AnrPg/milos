defmodule Palee.Application.Ports.ImageDescriber do
  @moduledoc """
  Suggests a short alternative text for a photo (ADR-157), in the person's
  language. The suggestion goes back to the person only; nothing is saved.
  """

  @type image :: %{bytes: binary(), content_type: String.t()}
  @type options :: %{locale: String.t()}

  @typedoc "Who the call is made for, so its model usage is metered (ADR-152)."
  @type metering :: %{
          optional(:organization_id) => String.t() | nil,
          optional(:user_id) => String.t() | nil,
          optional(:operation_id) => String.t(),
          optional(:feature) => String.t()
        }

  @callback describe(image(), options(), metering()) ::
              {:ok, String.t()} | {:error, :not_configured} | {:error, term()}
end
