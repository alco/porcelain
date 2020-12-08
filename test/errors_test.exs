defmodule PorcelainTest.ErrorsTest do
  use ExUnit.Case

  import Porcelain, only: [shell: 2, exec: 2]
  alias Porcelain.Result

  test "bad option" do
    :ok = Porcelain.reinit(Porcelain.Driver.Basic)

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
    :ok = Porcelain.reinit(Porcelain.Driver.Basic)

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

  test "non-existent program, but folder of that name [basic, noshell]" do
    assert exec("lib", [])
           == {:error, "Command not found: lib"}

    assert Porcelain.spawn("lib", [])
           == {:error, "Command not found: lib"}
  end

  @tag :posix
  @tag :goon
  test "non-existent program [goon, shell, redirect]" do
    :ok = Porcelain.reinit(Porcelain.Driver.Goon)

    result = shell("whatever", err: :out)
    assert %Result{err: :out, out: <<_::binary>>, status: 127}
           = result
    assert result.out =~ ~r/whatever: .*?not found/
  end

  @tag :posix
  @tag :goon
  test "non-existent program [goon, shell]" do
    :ok = Porcelain.reinit(Porcelain.Driver.Goon)

    result = shell("whatever", err: :string)
    assert %Result{err: <<_::binary>>, out: "", status: 127}
           = result
    assert result.err =~ ~r/whatever: .*?not found/
  end

  @tag :goon
  test "non-existent program [goon, noshell]" do
    :ok = Porcelain.reinit(Porcelain.Driver.Goon)

    assert exec("whatever", [])
           == {:error, "Command not found: whatever"}

    assert Porcelain.spawn("whatever", [])
           == {:error, "Command not found: whatever"}
  end
end
