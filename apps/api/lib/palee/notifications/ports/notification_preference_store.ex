defmodule Palee.Notifications.Ports.NotificationPreferenceStore do
  @moduledoc "Persistence port of a person's notification choices (ADR-199); every call is the context user's own."

  @type choice :: %{category: String.t(), channel: String.t(), enabled: boolean()}

  @callback list(context :: map()) :: [choice()]
  @doc "Stores each channel → enabled pair of one category, in one statement."
  @callback put(context :: map(), String.t(), [{String.t(), boolean()}], DateTime.t()) ::
              :ok | {:error, term()}
end
