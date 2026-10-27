defmodule Palee.Application.EmailChangeHooks do
  @moduledoc """
  ADR-207: what else must follow a login's email to its new address (for
  example corporate seats granted by an email domain). `run/3` calls each
  hook as `fun(login_id, old_email, new_email)` once a change, or its
  revert, has committed.

  To register, add `{Module, :function}` to `@hooks`. A hook whose module
  is not compiled into this build is skipped, so a feature can list itself
  before it lands. A hook that raises is logged and never undoes the email
  change: hooks run after the commit.
  """

  require Logger

  @hooks [
    # Corporate seats bound to an email domain (agent verified-gates' rows 15, 11, 14).
    {Palee.Application.CorporateSeats, :email_changed}
  ]

  @doc "The registered hooks, as `{module, function}`."
  def hooks, do: Application.get_env(:palee, :email_change_hooks, @hooks)

  @doc "Runs every available hook; always `:ok`."
  def run(login_id, old_email, new_email) do
    Enum.each(hooks(), fn {module, function} ->
      if Code.ensure_loaded?(module) and function_exported?(module, function, 3) do
        try do
          apply(module, function, [login_id, old_email, new_email])
        rescue
          error ->
            # The struct name only: a message could carry an address.
            Logger.error(
              "email change hook #{inspect(module)}.#{function} failed: #{inspect(error.__struct__)}"
            )
        end
      end
    end)
  end
end
