defmodule PorcelainTest.ErrorsTest do
  use ExUnit.Case

  import Porcelain, only: [shell: 2, exec: 2]
  alias Porcelain.Result

  test "bad option" do
    msg = "Invalid options: [option: \"value\"]"
    assert_raise Porcelain.UsageError, msg, fn ->
      shell("whatever", option: "value")
    end

    msg = "Invalid options: [in: :receive]"
    assert_raise Porcelain.UsageError, msg, fn ->
      shell("whatever", in: :receive)
    end
  end

  test "non-existent program" do
    result = shell("whatever", err: :out)
    assert %Result{err: :out, out: <<_::binary>>, status: 127}
           = result
    assert result.out =~ ~r/exec: whatever: not found/

    assert exec("whatever", [])
           == {:error, "Command not found: whatever"}
  end
end
