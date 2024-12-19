defmodule RestrictedRuntimeTest do
  use ExUnit.Case
  doctest RestrictedRuntime

  test "greets the world" do
    assert RestrictedRuntime.hello() == :world
  end
end
