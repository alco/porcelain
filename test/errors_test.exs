defmodule PorcelainTest.ErrorsTest do
  use ExUnit.Case

  import Porcelain, only: [shell: 2, exec: 2]
  alias Porcelain.Result

  test "bad option" do
    Porcelain.reinit(Porcelain.Driver.Basic)

    msg = "Invalid options: [option: \"value\"]"
    assert_raise Porcelain.UsageError, msg, fn ->
      shell("whatever", option: "value")
    end

    msg = "Invalid options: [in: :receive]"
    assert_raise Porcelain.UsageError, msg, fn ->
      shell("whatever", in: :receive)
    end
  end

  @tag :posix
  test "non-existent program [basic, shell]" do
    Porcelain.reinit(Porcelain.Driver.Basic)

    result = shell("whatever", err: :out)
    assert %Result{err: :out, out: <<_::binary>>, status: 127}
           = result
    assert result.out =~ ~r/whatever: .*?not found/
  end

  test "non-existent program [basic, noshell]" do
    assert exec("whatever", [])
           == {:error, "Command not found: whatever"}

    assert Porcelain.spawn("whatever", [])
           == {:error, "Command not found: whatever"}
  end

  @tag :posix
  test "non-existent program [goon, shell]" do
    Porcelain.reinit(Porcelain.Driver.Goon)

    result = shell("whatever", err: :out)
    assert %Result{err: :out, out: <<_::binary>>, status: 127}
           = result
    assert result.out =~ ~r/whatever: .*?not found/
  end

  test "non-existent program [goon, noshell]" do
    Porcelain.reinit(Porcelain.Driver.Goon)

    assert exec("whatever", [])
           == {:error, "Command not found: whatever"}

    assert Porcelain.spawn("whatever", [])
           == {:error, "Command not found: whatever"}
  end
end
