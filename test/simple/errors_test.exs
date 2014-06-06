defmodule PorcelainTest.SimpleErrorsTest do
  use ExUnit.Case

  # TODO: throw exceptions

  import Porcelain, only: [shell: 2, exec: 2]
  alias Porcelain.Result

  test "bad option" do
    assert shell("whatever", option: "value")
           == {:error, "Invalid options: [option: \"value\"]"}
    assert shell("whatever", in: :receive)
           == {:error, "Invalid options: [in: :receive]"}
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
