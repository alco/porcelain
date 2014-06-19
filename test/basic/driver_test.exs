defmodule PorcelainTest.BasicTest do
  use ExUnit.Case

  import TestUtil
  import Porcelain, only: [shell: 1, shell: 2, exec: 2, exec: 3]

  alias Porcelain.Result

  setup_all do
    Porcelain.reinit(Porcelain.Driver.Basic)
  end

  test "status" do
    assert exec("date", [], out: nil)
           == %Result{out: nil, err: nil, status: 0}
  end

  test "stdout" do
    assert exec("echo", [], out: nil) == %Result{out: nil, err: nil, status: 0}
    assert exec("echo", []) == %Result{out: "\n", err: nil, status: 0}

    assert exec("echo", ["-n", "Hello", "world"], out: :string)
           == %Result{out: "Hello world", err: nil, status: 0}
  end

  test "stderr" do
    assert exec("date", ["rubbish"], out: nil, err: :out)
           == %Result{out: nil, err: :out, status: 1}

    result = exec("date", ["rubbish"], err: :out)
    assert %Result{out: <<_::binary>>, err: :out, status: 1} = result
    assert result.out =~ ~r/illegal time format/
  end

  @tag :localbin
  test "local binary" do
    result = exec("goon", [], err: :out)
    assert %Result{out: <<_::binary>>, err: :out, status: 255} = result
    assert result.out =~ ~r/Please specify the protocol version/
  end

  @tag :localbin
  @tag :posix
  test "local binary [shell]" do
    result = shell("./goon", err: :out)
    assert %Result{out: <<_::binary>>, err: :out, status: 255} = result
    assert result.out =~ ~r/Please specify the protocol version/
  end

  test "dir" do
    assert exec("sort", ["input.txt"], dir: fixture_path(""))
           == %Result{out: "file\nfrom\ninput\n", err: nil, status: 0}
  end

  @tag :posix
  test "env" do
    cmd = "echo $custom_var"
    assert shell(cmd, env: [custom_var: "hello"])
           == %Result{out: "hello\n", err: nil, status: 0}
    assert shell(cmd, env: %{"custom_var" => "bye"})
           == %Result{out: "bye\n", err: nil, status: 0}
  end

  @tag :posix
  test "shell" do
    cmd = "head -n 4 | tr a-i A-I | sort"
    input = "Alphabetical\nlist\nof\nlines\n"
    output = "AlpHABEtICAl\nlInEs\nlIst\noF\n"
    assert shell(cmd, in: input) == %Result{out: output, err: nil, status: 0}

    cmd = "head -n 4 >/dev/null"
    assert shell(cmd, in: input) == %Result{out: "", err: nil, status: 0}

    cmd = "date rubbish 2>&1"
    result = shell(cmd, in: input)
    assert %Result{out: <<_::binary>>, err: nil, status: 1} = result
    assert result.out =~ ~r/illegal time format/
  end

  test "input string" do
    assert exec("grep", [">end<", "-m", "2"],
                    in: "hi\n>end< once\nbye\n>end< twice\n")
           == %Result{out: ">end< once\n>end< twice\n", err: nil, status: 0}
  end

  test "input iodata" do
    input = ["hi\n", [?>, [?e, ?n], "d< onc"],
                    "e\nb", ["y", ["e", ?\n], ">end< twice\n"]]
    assert exec("grep", [">end<", "-m", "2"], in: input)
           == %Result{out: ">end< once\n>end< twice\n", err: nil, status: 0}
  end

  test "input stream" do
    input = Stream.concat(["hello", ["th", [?i, ?s], "is \nthe"], [">e"]],
                          [[[?n, "d<\n"], "again\n"], ">e", "nd< final", ?\n])
    assert exec("grep", [">end<", "-m", "2"], in: input)
           == %Result{out: "the>end<\n>end< final\n", err: nil, status: 0}

    stream = File.stream!(fixture_path("input.txt"))
    assert exec("head", ["-n", "3"], in: stream)
           == %Result{out: "input\nfrom\nfile\n", err: nil, status: 0}
  end

  @tag :posix
  test "input path" do
    cmd = "head -n 3 | sort"
    path = fixture_path("input.txt")
    assert shell(cmd, in: {:path, path})
           == %Result{out: "file\nfrom\ninput\n", err: nil, status: 0}
  end

  @tag :posix
  test "input file" do
    cmd = "head -n 3 | sort -r"
    path = fixture_path("input.txt")
    File.open(path, fn file ->
      assert shell(cmd, in: {:file, file})
             == %Result{out: "input\nfrom\nfile\n", err: nil, status: 0}
    end)
  end

  test "async input" do
    assert exec("grep", [">end<", "-m", "2"], in: "hi\n>end< once\nbye\n>end< twice\n", async_in: true)
           == %Result{out: ">end< once\n>end< twice\n", err: nil, status: 0}
  end

  @tag :posix
  test "output iodata" do
    cmd = "head -n 4 | sort"
    result = shell(cmd, in: "this\nis\nthe\nend\n", out: :iodata)
    assert %Result{out: [_|_], err: nil, status: 0} = result
    assert IO.iodata_to_binary(result.out) == "end\nis\nthe\nthis\n"
  end

  @tag :posix
  test "output path" do
    cmd = "head -n 4 | sort"
    outpath = Path.join(System.tmp_dir, "tmpoutput")
    File.rm_rf!(outpath)
    assert shell(cmd, in: "this\nis\nthe\nend\n", out: {:path, outpath})
           == %Result{out: {:path, outpath}, err: nil, status: 0}
    assert File.read!(outpath) == "end\nis\nthe\nthis\n"
  end

  @tag :posix
  test "output append" do
    cmd = "head -n 4 | sort"
    outpath = Path.join(System.tmp_dir, "tmpoutput")
    File.write!(outpath, "hello.")
    assert shell(cmd, in: "this\nis\nthe\nend\n", out: {:append, outpath})
           == %Result{out: {:path, outpath}, err: nil, status: 0}
    assert File.read!(outpath) == "hello.end\nis\nthe\nthis\n"
  end

  @tag :posix
  test "output file" do
    cmd = "head -n 3 | sort"
    inpath = fixture_path("input.txt")
    outpath = Path.join(System.tmp_dir, "tmpoutput")
    File.rm_rf!(outpath)
    File.open(outpath, [:write], fn file ->
      :ok = IO.write(file, "hello.")
      pos = 4
      {:ok, ^pos} = :file.position(file, pos)
      assert shell(cmd, in: {:path, inpath}, out: {:file, file})
             == %Result{out: {:file, file}, err: nil, status: 0}
    end)
    assert File.read!(outpath) == "hellfile\nfrom\ninput\n"
  end

  @tag :posix
  test "collectable output" do
    import ExUnit.CaptureIO

    cmd = "head -n 7 | sort"
    input = "b\nd\nz\na\nc\ng\nO\n"
    stream = IO.binstream(:stdio, :line)
    assert capture_io(fn ->
      assert shell(cmd, in: input, out: {:into, stream})
             == %Result{out: {:into, stream}, err: nil, status: 0}
    end) == "O\na\nb\nc\nd\ng\nz\n"
  end
end
