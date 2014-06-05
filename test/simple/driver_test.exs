defmodule PorcelainTest.SimpleTest do
  use ExUnit.Case

  import TestUtil
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
    assert exec(cmd, out: :string)
           == %Result{out: "Hello world", err: nil, status: 0}
  end

  test "stderr" do
    cmd = {"date", ["rubbish"]}
    assert exec(cmd, out: nil, err: :out)
           == %Result{out: nil, err: :out, status: 1}

    result = exec(cmd, err: :out)
    assert %Result{out: <<_::binary>>, err: :out, status: 1} = result
    assert result.out =~ ~r/illegal time format/
  end

  test "input string" do
    cmd = {"grep", [">end<", "-m", "2"]}
    assert exec(cmd, in: "hi\n>end< once\nbye\n>end< twice\n")
           == %Result{out: ">end< once\n>end< twice\n", err: nil, status: 0}
  end

  test "async input" do
    cmd = {"grep", [">end<", "-m", "2"]}
    assert exec(cmd, in: "hi\n>end< once\nbye\n>end< twice\n", async_in: true)
           == %Result{out: ">end< once\n>end< twice\n", err: nil, status: 0}
  end

  test "input iodata" do
    cmd = {"grep", [">end<", "-m", "2"]}
    input = ["hi\n", [?>, [?e, ?n], "d< onc"],
                    "e\nb", ["y", ["e", ?\n], ">end< twice\n"]]
    assert exec(cmd, in: input)
           == %Result{out: ">end< once\n>end< twice\n", err: nil, status: 0}
  end

  test "input stream" do
    cmd = {"grep", [">end<", "-m", "2"]}
    input = Stream.concat(["hello", ["th", [?i, ?s], "is \nthe"], [">e"]],
                          [[[?n, "d<\n"], "again\n"], ">e", "nd< final", ?\n])
    assert exec(cmd, in: input)
           == %Result{out: "the>end<\n>end< final\n", err: nil, status: 0}
  end

  test "input path" do
    cmd = "head -n 3 | sort"
    path = fixture_path("input.txt")
    assert exec(cmd, in: {:path, path})
           == %Result{out: "file\nfrom\ninput\n", err: nil, status: 0}
  end

  test "input file" do
    cmd = "head -n 3 | sort"
    path = fixture_path("input.txt")
    File.open(path, fn file ->
      assert exec(cmd, in: {:file, file})
             == %Result{out: "file\nfrom\ninput\n", err: nil, status: 0}
    end)
  end

  test "shell" do
    cmd = "head -n 4 | tr a-c A-C | sort"
    input = "Alphabetical\nlist\nof\nlines\n"
    output = "AlphABetiCAl\nlines\nlist\nof\n"
    assert exec(cmd, in: input) == %Result{out: output, err: nil, status: 0}

    cmd = "head -n 4 >/dev/null"
    assert exec(cmd, in: input) == %Result{out: "", err: nil, status: 0}
  end

  test "output iodata" do
    cmd = "head -n 4 | sort"
    result = exec(cmd, in: "this\nis\nthe\nend\n", out: :iodata)
    assert %Result{out: [_|_], err: nil, status: 0} = result
    assert IO.iodata_to_binary(result.out) == "end\nis\nthe\nthis\n"
  end

  test "output path" do
    cmd = "head -n 4 | sort"
    outpath = Path.join(System.tmp_dir, "tmpoutput")
    File.rm_rf!(outpath)
    assert exec(cmd, in: "this\nis\nthe\nend\n", out: {:path, outpath})
           == %Result{out: {:path, outpath}, err: nil, status: 0}
    assert File.read!(outpath) == "end\nis\nthe\nthis\n"
  end

  test "output append" do
    cmd = "head -n 4 | sort"
    outpath = Path.join(System.tmp_dir, "tmpoutput")
    File.write!(outpath, "hello.")
    assert exec(cmd, in: "this\nis\nthe\nend\n", out: {:append, outpath})
           == %Result{out: {:path, outpath}, err: nil, status: 0}
    assert File.read!(outpath) == "hello.end\nis\nthe\nthis\n"
  end

  test "output file" do
    cmd = "head -n 3 | sort"
    inpath = fixture_path("input.txt")
    outpath = Path.join(System.tmp_dir, "tmpoutput")
    File.rm_rf!(outpath)
    File.open(outpath, [:write], fn file ->
      assert exec(cmd, in: {:path, inpath}, out: {:file, file})
             == %Result{out: {:file, file}, err: nil, status: 0}
    end)
    assert File.read!(outpath) == "file\nfrom\ninput\n"
  end

  test "errors: bad option" do
    assert exec("whatever", option: "value")
           == {:error, "Invalid options: [option: \"value\"]"}
    assert exec("whatever", in: :receive)
           == {:error, "Invalid options: [in: :receive]"}
  end

  test "errors: non-existent program" do
    result = exec("whatever", err: :out)
    assert %Result{err: :out, out: <<_::binary>>, status: 127}
           = result
    assert result.out =~ ~r/exec: whatever: not found/

    assert exec({"whatever", []})
           == {:error, "Command not found: whatever"}
  end
end
