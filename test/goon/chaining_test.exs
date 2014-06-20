defmodule PorcelainTest.ChainingTest do
  use ExUnit.Case

  alias Porcelain.Result
  alias Porcelain.Process, as: Proc

  setup_all do
    :ok = Porcelain.reinit(Porcelain.Driver.Goon)
  end

  test "multiple AND filters" do
    input = """
    squeak
    sponge
    silly
    abcdef
    elixir
    erlang
    """

    filter_a =
      %Proc{out: stream_a} =
        Porcelain.spawn("grep", ["a"], in: input, out: :stream)

    filter_e =
      %Proc{out: stream_e} =
        Porcelain.spawn("grep", ["e"], in: stream_a, out: :stream)

    assert Porcelain.exec("sort", [], in: stream_e, out: :string)
           == %Result{status: 0, out: "abcdef\nerlang\nsqueak\n", err: nil}

    refute Proc.alive?(filter_a)
    refute Proc.alive?(filter_e)
  end
end
