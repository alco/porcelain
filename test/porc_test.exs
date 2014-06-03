#defmodule PorcOutputsTest do
#  use ExUnit.Case, async: true
#
#  test "cat no input" do
#    assert {0, nil, nil} = Porc.call("cat")
#    assert {1, nil, nil} = Porc.call("cat -goo")
#  end
#
#  test "cat input pid" do
#    assert_raise RuntimeError, fn ->
#      Porc.call("cat", in: :pid)
#    end
#  end
#
#  test "cat no output" do
#    assert {0, nil, nil}
#           = Porc.call("cat", in: "Hello world!")
#  end
#
#  test "cat stdout buffer" do
#    assert {0, "Hello world!", nil}
#           = Porc.call("cat", in: "Hello world!", out: :buffer)
#  end
#
#  test "cat stdout pid" do
#    ref = make_ref
#    pidspec = {self, ref}
#    assert {0, ^pidspec, nil}
#           = Porc.call("cat", in: "Hello world!", out: pidspec)
#    assert_receive {^ref, :stdout, "Hello world!"}
#  end
#
#  test "cat stderr /dev/null" do
#    assert {1, nil, nil}
#           = Porc.call("cat -goo", in: "Hello world!")
#  end
#
#  test "cat stderr buffer" do
#    assert {1, nil, <<_::binary>>}
#           = Porc.call("cat -goo", in: "Hello world!", err: :buffer)
#  end
#
#  test "cat stderr pid" do
#    ref = make_ref
#    pidspec = {self, ref}
#    assert {1, nil, ^pidspec}
#           = Porc.call("cat -goo", in: "Hello world!", err: pidspec)
#    assert_receive {^ref, :stderr, <<_::binary>>}
#  end
#
#  test "cat from path" do
#    assert {0, "Input from file\n", nil}
#           = Porc.call("cat", in: {:path, inpath}, out: :buffer)
#  end
#
#  test "cat from file" do
#    File.open inpath, [:read], fn(file) ->
#      assert {0, "Input from file\n", nil}
#             = Porc.call("cat", in: {:file, file}, out: :buffer)
#    end
#  end
#
#  test "cat to path" do
#    path = outpath
#    pathspec = {:path, path}
#
#    assert !File.exists?(path)
#
#    assert {0, ^pathspec, nil}
#           = Porc.call("cat", in: "Hello world!", out: pathspec)
#    assert {:ok, "Hello world!"} = File.read(path)
#  after
#    File.rm outpath
#  end
#
#  test "cat to path append" do
#    path = outpath
#    assert !File.exists?(path)
#
#    Porc.call("cat", in: "Hello world!", out: {:path, path})
#
#    pathspec = {:append, path}
#    assert {0, ^pathspec, nil}
#           = Porc.call("cat", in: "\nSecond take", out: pathspec)
#    assert {:ok, "Hello world!\nSecond take"} = File.read(path)
#  after
#    File.rm outpath
#  end
#
#  defp inpath do
#    Path.join([__DIR__, "fixtures", "input.txt"])
#  end
#
#  defp outpath do
#    Path.join([__DIR__, "output.txt"])
#  end
#end
#
#defmodule PorcRedirectsTest do
#  use ExUnit.Case, async: true
#
#  test "cat stdout to stderr /dev/null" do
#    assert {0, nil, nil}
#           = Porc.call("cat", in: "Hello world!", out: :err)
#  end
#
#  test "cat stdout to stderr buffer" do
#    assert {0, nil, "Hello world!"}
#           = Porc.call("cat", in: "Hello world!", out: :err, err: :buffer)
#  end
#
#  test "cat stderr to stdout /dev/null" do
#    assert {1, nil, nil}
#           = Porc.call("cat -goo", in: "Hello world!", err: :out)
#  end
#
#  test "cat stderr to stdout buffer" do
#    assert {1, <<_::binary>>, nil}
#           = Porc.call("cat -goo", in: "Hello world!", err: :out, out: :buffer)
#  end
#end
