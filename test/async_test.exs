defmodule PorcelainAsyncOutputsTest do
  use ExUnit.Case, async: true

  alias Porcelain, as: Porc

  test "cat no input" do
    {pid, port} = Porc.spawn("cat")
    assert is_pid(pid)
    assert is_port(port)
    assert_receive {^pid, %Porc{status: 0, in: nil, out: nil, err: nil}}
  end

  test "cat input pid" do
    {pid, _} = Porc.spawn("cat", in: :pid)
    refute_receive _  # the port is waiting for communications

    Porc.send(pid, "some")
    Porc.send(pid, " input")
    refute_receive _  # still waiting for EOF

    Porc.send(pid, :eof)
    assert_receive {^pid, %Porc{status: 0, in: :pid, out: nil, err: nil}}
  end

  test "cat no output" do
    {pid, _} = Porc.spawn("cat", in: "Hello world!")
    assert_receive {^pid, %Porc{status: 0, in: "Hello world!", out: nil, err: nil}}
  end

  test "cat stdout buffer" do
    string = "Hello world!"
    {pid, _} = Porc.spawn("cat", in: string, out: :buffer)
    assert_receive {^pid, %Porc{status: 0, in: ^string, out: ^string, err: nil}}
  end

  test "cat stdout pid" do
    string = "Hello world!"

    ref = make_ref
    pidspec = {self, ref}

    {pid, _} = Porc.spawn("cat", in: string, out: pidspec)
    assert_receive {^pid, %Porc{status: 0, in: ^string, out: ^pidspec, err: nil}}
    assert_receive {^ref, :stdout, ^string}
  end

  test "cat stderr /dev/null" do
    string = "Hello world!"
    {pid, _} = Porc.spawn("cat -goo", in: string)
    assert_receive {^pid, %Porc{status: 1, in: ^string, out: nil, err: nil}}
  end

  test "cat stderr buffer" do
    string = "Hello world!"
    {pid, _} = Porc.spawn("cat -goo", in: string, err: :buffer)
    assert_receive {^pid, %Porc{status: 1, in: ^string, out: nil, err: <<_::binary>>}}
  end

  test "cat stderr pid" do
    string = "Hello world!"

    ref = make_ref
    pidspec = {self, ref}

    {pid, _} = Porc.spawn("cat -goo", in: string, err: pidspec)
    assert_receive {^pid, %Porc{status: 1, in: ^string, out: nil, err: ^pidspec}}
    assert_receive {^ref, :stderr, <<_::binary>>}
  end

  test "cat from path" do
    pathspec = {:path, inpath}
    {pid, _} = Porc.spawn("cat", in: pathspec, out: :buffer)
    assert_receive {^pid, %Porc{status: 0, in: ^pathspec, out: "Input from file\n", err: nil}}
  end

  test "cat from file" do
    {:ok, file} = File.open inpath
    filespec = {:file, file}

    {pid, _} = Porc.spawn("cat", in: filespec, out: :buffer)
    assert_receive {^pid, %Porc{status: 0, in: ^filespec, out: "Input from file\n", err: nil}}

    File.close file
  end

  test "cat to path" do
    path = outpath
    pathspec = {:path, path}

    assert !File.exists?(path)

    {pid, _} = Porc.spawn("cat", in: "Hello world!", out: pathspec)
    assert_receive {^pid, %Porc{status: 0, in: "Hello world!", out: ^pathspec, err: nil}}

    assert {:ok, "Hello world!"} = File.read(path)
  after
    File.rm outpath
  end

  test "cat to path append" do
    path = outpath
    assert !File.exists?(path)

    Porc.call("cat", in: "Hello world!", out: {:path, path})

    pathspec = {:append, path}
    {pid, _} = Porc.spawn("cat", in: "\nSecond take", out: pathspec)
    assert_receive {^pid, %Porc{status: 0, in: "\nSecond take", out: ^pathspec, err: nil}}

    assert {:ok, "Hello world!\nSecond take"} = File.read(path)
  after
    File.rm outpath
  end

  defp inpath do
    Path.join([__DIR__, "fixtures", "input.txt"])
  end

  defp outpath do
    Path.join([__DIR__, "output.txt"])
  end
end

defmodule PorcelainAsyncRedirectsTest do
  use ExUnit.Case, async: true

  alias Porcelain, as: Porc

  test "cat stdout to stderr /dev/null" do
    {pid, _} = Porc.spawn("cat", in: "Hello world!", out: :err)
    assert_receive {^pid, %Porc{status: 0, in: "Hello world!", out: nil, err: nil}}
  end

  test "cat stdout to stderr buffer" do
    {pid, _} = Porc.spawn("cat", in: "Hello world!", out: :err, err: :buffer)
    assert_receive {^pid, %Porc{status: 0, in: "Hello world!", out: nil, err: "Hello world!"}}
  end

  test "cat stderr to stdout /dev/null" do
    {pid, _} = Porc.spawn("cat -goo", in: "Hello world!", err: :out)
    assert_receive {^pid, %Porc{status: 1, in: "Hello world!", out: nil, err: nil}}
  end

  test "cat stderr to stdout buffer" do
    {pid, _} = Porc.spawn("cat -goo", in: "Hello world!", err: :out, out: :buffer)
    assert_receive {^pid, %Porc{status: 1, in: "Hello world!", out: <<_::binary>>, err: nil}}
  end
end
