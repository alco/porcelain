defmodule PorcelainTest.SimpleTest do
  use ExUnit.Case

  import Porcelain, only: [exec: 1, exec: 2]
  alias Porcelain.Result

  test "status" do
    cmd = {"date", []}
    assert exec(cmd, out: nil) == %Result{out: nil, err: nil, status: 0}

    cmd = {"date", ["rubbish"]}
    assert exec(cmd, out: nil) == %Result{out: nil, err: nil, status: 1}
  end

  test "stdout" do
    cmd = {"echo", []}
    assert exec(cmd, out: nil) == %Result{out: nil, err: nil, status: 0}
    assert exec(cmd) == %Result{out: "\n", err: nil, status: 0}

    cmd = {"echo", ["-n", "Hello", "world"]}
    assert exec(cmd, out: :buffer)
           == %Result{out: "Hello world", err: nil, status: 0}
  end

  test "stderr" do
    cmd = {"date", ["rubbish"]}
    assert exec(cmd, out: nil, err: :out) == %Result{out: nil, err: :out, status: 1}

    result = exec(cmd, err: :out)
    assert %Result{out: <<_::binary>>, err: :out, status: 1} = result
    assert result.out =~ ~r/illegal time format/
  end

  test "input" do
    cmd = {"grep", [">end<", "-m", "2"]}
    assert exec(cmd, in: "hi\n>end< once\nbye\n>end< twice\n")
           == %Result{out: ">end< once\n>end< twice\n", err: nil, status: 0}
  end

  test "shell" do
    cmd = "head -n 4 | tr a-c A-C | sort"
    input = "Alphabetical\nlist\nof\nlines\n"
    output = "AlphABetiCAl\nlines\nlist\nof\n"
    assert exec(cmd, in: input) == %Result{out: output, err: nil, status: 0}
  end
end
