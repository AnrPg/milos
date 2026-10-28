defmodule Palee.TestSupport.SampleEmail do
  @moduledoc """
  `:sample_notice`, a template registered only in tests (config/test.exs)
  for the outbox's own tests: a heading, a paragraph and a button.
  Assigns: `name`, `url`. No throttle of its own: the category's default.
  """

  use Palee.Email.Template, category: :transactional

  @impl true
  def subject(%{name: name}, _locale), do: "Hello #{name}"

  @impl true
  def text(%{name: name, url: url}, locale),
    do: Layout.text(locale, ["Hello #{name}", Layout.text_button("Open", url)])

  @impl true
  def html(%{name: name, url: url}, locale),
    do: Layout.html(locale, [Layout.heading("Hello #{name}"), Layout.button("Open", url)])
end
