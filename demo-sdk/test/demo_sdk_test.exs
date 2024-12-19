defmodule DemoSDKTest do
  use ExUnit.Case
  doctest DemoSDK

  test "greets the world" do
    assert DemoSDK.hello() == :world
  end
end
