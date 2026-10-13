defmodule MilosTrainingWeb.OpenApiSpecCacheTest do
  # Regression guard for the BEAM `literal_alloc` crash (ADR-134): every
  # `:persistent_term.put/2` copies the ~20 MB spec into the literal area, so
  # the adapter must store it once and never re-put it per controller action.
  use ExUnit.Case, async: true

  alias MilosTrainingWeb.OpenApiSpecCache

  setup do
    on_exit(fn -> OpenApiSpecCache.erase(__MODULE__) end)
  end

  test "is the configured OpenApiSpex cache adapter" do
    assert OpenApiSpex.Plug.Cache.adapter() == OpenApiSpecCache
  end

  test "stores the spec once and ignores later puts" do
    assert OpenApiSpecCache.get(__MODULE__) == nil

    first = {%{spec: 1}, %{"op" => :operation}}
    assert OpenApiSpecCache.put(__MODULE__, first) == :ok

    second = {%{spec: 1}, %{"op" => :operation, {Controller, :action} => :operation}}
    assert OpenApiSpecCache.put(__MODULE__, second) == :ok

    assert OpenApiSpecCache.get(__MODULE__) == first
  end

  test "erase/1 drops the stored spec" do
    :ok = OpenApiSpecCache.put(__MODULE__, {%{}, %{}})
    assert OpenApiSpecCache.erase(__MODULE__) == :ok
    assert OpenApiSpecCache.get(__MODULE__) == nil
  end
end
