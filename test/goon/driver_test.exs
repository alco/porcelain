defmodule PorcelainTest.GoonTest do
  use ExUnit.Case

  import TestUtil
  import Porcelain, only: [exec: 2, exec: 3]

  alias Porcelain.Result

  @moduletag :goon

  setup_all do
    Porcelain.reinit(Porcelain.Driver.Goon)
  end

  test "status" do
    assert exec("date", [], out: nil)
           == %Result{out: nil, err: nil, status: 0}

    assert exec("date", ["rubbish"], out: nil)
           == %Result{out: nil, err: nil, status: 1}
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

    result = exec("date", ["rubbish"], out: nil, err: :string)
    assert %Result{out: nil, err: <<_::binary>>, status: 1} = result
    assert result.err =~ ~r/date: (illegal|invalid)/
  end

  test "stderr redirect" do
    result = exec("date", ["rubbish"], err: :out)
    assert %Result{out: <<_::binary>>, err: :out, status: 1} = result
    assert result.out =~ ~r/date: (illegal|invalid)/
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
    result = Porcelain.shell("./goon", err: :out)
    assert %Result{out: <<_::binary>>, err: :out, status: 255} = result
    assert result.out =~ ~r/Please specify the protocol version/
  end

  test "dir" do
    assert exec("sort", ["input.txt"], dir: fixture_path(""))
           == %Result{out: "file\nfrom\ninput\n", err: nil, status: 0}
  end

  test "env" do
    cmd = "echo $custom_var"
    assert Porcelain.shell(cmd, env: [custom_var: "hello"])
           == %Result{out: "hello\n", err: nil, status: 0}
    assert Porcelain.shell(cmd, env: %{"custom_var" => "bye"})
           == %Result{out: "bye\n", err: nil, status: 0}
  end

  test "shell" do
    cmd = "tr a-i A-I | sort"
    input = "Alphabetical\nlist\nof\nlines\n"
    output = "AlpHABEtICAl\nlInEs\nlIst\noF\n"
    assert Porcelain.shell(cmd, in: input)
           == %Result{out: output, err: nil, status: 0}

    cmd = "cat >/dev/null"
    assert Porcelain.shell(cmd, in: input)
           == %Result{out: "", err: nil, status: 0}
  end

  test "input string" do
    assert exec("grep", [">end<"], in: "hi\n>end< once\nbye\n>end< twice\n")
           == %Result{out: ">end< once\n>end< twice\n", err: nil, status: 0}
  end

  test "input iodata" do
    input = ["hi\n", [?>, [?e, ?n], "d< onc"],
                    "e\nb", ["y", ["e", ?\n], ">end< twice\n"]]
    assert exec("grep", [">end<"], in: input)
           == %Result{out: ">end< once\n>end< twice\n", err: nil, status: 0}
  end

  test "input stream" do
    input = Stream.concat(["hello", ["th", [?i, ?s], "is \nthe"], [">e"]],
                          [[[?n, "d<\n"], "again\n"], ">e", "nd< final", ?\n])
    assert exec("grep", [">end<"], in: input)
           == %Result{out: "the>end<\n>end< final\n", err: nil, status: 0}

    stream = File.stream!(fixture_path("input.txt"))
    assert exec("cat", [], in: stream)
           == %Result{out: "input\nfrom\nfile\n", err: nil, status: 0}
  end

  test "input path" do
    path = fixture_path("input.txt")
    assert exec("sort", [], in: {:path, path})
           == %Result{out: "file\nfrom\ninput\n", err: nil, status: 0}
  end

  test "input file" do
    path = fixture_path("input.txt")
    File.open(path, fn file ->
      assert exec("sort", ["-r"], in: {:file, file})
             == %Result{out: "input\nfrom\nfile\n", err: nil, status: 0}
    end)
  end

  test "async input" do
    assert exec("grep", [">end<"], in: "hi\n>end< once\nbye\n>end< twice\n", async_in: true)
           == %Result{out: ">end< once\n>end< twice\n", err: nil, status: 0}
  end

  test "output iodata" do
    result = exec("sort", [], in: "this\nis\nthe\nend\n", out: :iodata)
    assert %Result{out: [_|_], err: nil, status: 0} = result
    assert IO.iodata_to_binary(result.out) == "end\nis\nthe\nthis\n"
  end

  test "output path" do
    outpath = Path.join(System.tmp_dir, "tmpoutput")
    File.rm_rf!(outpath)
    assert exec("sort", [], in: "this\nis\nthe\nend\n", out: {:path, outpath})
           == %Result{out: {:path, outpath}, err: nil, status: 0}
    assert File.read!(outpath) == "end\nis\nthe\nthis\n"
  end

  test "output append" do
    outpath = Path.join(System.tmp_dir, "tmpoutput")
    File.write!(outpath, "hello.")
    assert exec("sort", [], in: "this\nis\nthe\nend\n", out: {:append, outpath})
           == %Result{out: {:path, outpath}, err: nil, status: 0}
    assert File.read!(outpath) == "hello.end\nis\nthe\nthis\n"
  end

  test "output file" do
    inpath = fixture_path("input.txt")
    outpath = Path.join(System.tmp_dir, "tmpoutput")
    File.rm_rf!(outpath)
    File.open(outpath, [:write], fn file ->
      :ok = IO.write(file, "hello.")
      pos = 4
      {:ok, ^pos} = :file.position(file, pos)
      assert exec("sort", [], in: {:path, inpath}, out: {:file, file})
             == %Result{out: {:file, file}, err: nil, status: 0}
    end)
    assert File.read!(outpath) == "hellfile\nfrom\ninput\n"
  end

  test "collectable output" do
    import ExUnit.CaptureIO

    input = "b\nd\nz\na\nc\ng\n"
    stream = IO.binstream(:stdio, :line)
    assert capture_io(fn ->
      assert exec("sort", [], in: input, out: stream)
             == %Result{out: stream, err: nil, status: 0}
    end) == "a\nb\nc\nd\ng\nz\n"
  end

  test "collectable stderr" do
    import ExUnit.CaptureIO

    input = "b\nd\nz\na\nc\ng\n"
    stream = IO.binstream(:stdio, :line)
    opts = [in: input, out: nil, err: stream]
    assert capture_io(fn ->
      assert Porcelain.shell("sort 1>&2", opts)
             == %Result{out: nil, err: stream, status: 0}
    end) == "a\nb\nc\nd\ng\nz\n"
  end

  test "large input" do
    # the input should be largen than what can fit in a packet preceded with
    # 2-byte length
    small_size = 256 * 256             # 2 packets
    large_size = (256 * 256 - 1) * 10  # 10 packets
    megabyte = 1024 * 1024
    small_input = String.duplicate("a", small_size)
    large_input = String.duplicate("b", large_size)
    very_large_input = String.duplicate("c\n", megabyte)

    assert %Porcelain.Result{out: out, status: 0}
           = Porcelain.exec("wc", ["-c"], in: small_input)
    assert String.trim(out) == "#{small_size}"

    assert %Porcelain.Result{out: out, status: 0}
           = Porcelain.exec("wc", ["-c"], in: large_input)
    assert String.trim(out) == "#{large_size}"

    assert %Porcelain.Result{out: out, status: 0}
           = Porcelain.exec("wc", ["-l"], in: very_large_input)
    assert String.trim(out) == "#{megabyte}"
  end
end
