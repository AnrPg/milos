defmodule Palee.Email.Template do
  @moduledoc """
  The behaviour of one email kind (ADR-203). A template renders its subject,
  plain-text body and HTML body from the caller's `assigns` in `locale`;
  `Palee.Email.enqueue/4` renders all three once, at enqueue time.

  A template module:

      defmodule Palee.Email.Templates.VerifyEmail do
        use Palee.Email.Template, category: :account

        @impl true
        def subject(_assigns, locale), do: t(locale, "Confirm your email address")

        @impl true
        def text(%{url: url}, locale),
          do: Layout.text(locale, [t(locale, "..."), Layout.text_button(t(locale, "Confirm"), url)])

        @impl true
        def html(%{url: url}, locale),
          do: Layout.html(locale, [Layout.paragraph(t(locale, "...")), Layout.button(t(locale, "Confirm"), url)])
      end

  and one line in `Palee.Email.Templates`. `use` brings `Layout` (aliased),
  `t/3` (the `emails` gettext domain) and a `category/0` from the option.
  `throttle/0` is optional: the category's default applies without it.
  """

  alias Palee.Email.Domain.SendingPolicy

  @type assigns :: map()
  @type locale :: String.t()

  @doc "`:security`, `:account` or `:transactional` (see `SendingPolicy`)."
  @callback category() :: SendingPolicy.category()
  @callback subject(assigns(), locale()) :: String.t()
  @callback text(assigns(), locale()) :: String.t()
  @callback html(assigns(), locale()) :: String.t()

  @doc "How often this kind may go to one address (`SendingPolicy.throttle/3`)."
  @callback throttle() :: SendingPolicy.throttle()

  @optional_callbacks throttle: 0

  defmacro __using__(opts) do
    category = Keyword.fetch!(opts, :category)

    unless category in SendingPolicy.categories() do
      raise ArgumentError, "unknown email category #{inspect(category)}"
    end

    quote do
      @behaviour Palee.Email.Template

      alias Palee.Email.Layout, warn: false

      @impl Palee.Email.Template
      def category, do: unquote(category)

      @compile {:nowarn_unused_function, [t: 2, t: 3]}
      defp t(locale, message, bindings \\ %{}),
        do: Palee.Email.Layout.t(locale, message, bindings)
    end
  end
end
