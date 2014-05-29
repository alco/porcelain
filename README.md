Porcelain
=========

**The library is undergoing a revamp. Some things in this README are a lie**

Launch and communicate with external OS processes in Elixir without limitations
of Erlang ports. Porcelain builds on ports for easy integration, but provides
richer functionality and simple API for managing external processes.

## Prerequisites

Porcelain relies on one external dependency to provide some of its features:
[goon](https://github.com/alco/goon). Get the binary for your OS and put it in
your application's working directory or somewhere in your `$PATH`.

In case `goon` is not found, Porcelain will fall back to the pure Elixir driver.

## Usage

### Synchronous API

```elixir
alias Porcelain, as: Porc

## Capture stdout
Porc.call("cat", in: "Hello world!")
#=> {0, "Hello world!", ""}

## Capture stderr
Porc.call("cat -g", in: "Hello world!")
#=> {0, "", "cat: illegal option -- g\nusage: cat [-benstuv] [file ...]\n"}

## Receive output as messages
ref = make_ref()
Porc.call("cat", in: "Hello world!", out: {self, ref})
iex> flush
#=> {#Reference<0.0.0.207>, :stdout, "Hello world!"}

## Using files for input and output
File.open "data.txt", [:read], fn(f_in) ->
  File.open "output.txt", [:write], fn(f_out) ->
    Porc.call("cat", in: {:file, f_in}, out: {:file, f_out})
  end
end
#=> {0, {:file, #PID<0.48.0>}, ""}
```
```sh
$ cat data.txt
Input from tile
$ cat output.txt
Input from tile
```

### Async API

```elixir
alias Porcelain, as: Porc

{pid, _port} = Porc.spawn("cat", in: :pid, out: :buffer)

Porc.send(pid, "Hello")
Porc.send(pid, "\nWorld")
Porc.send(pid, :eof)

iex> flush
#=> {#PID<0.51.0>, %Porc{status: 0, in: :pid, out: "Hello\nWorld", err: nil}}
```

### Stream API

It is possible to spawn multiple process and chain them together. One can also
use sockets and Elixir streams as sources of input.

```elixir
sock = :gen_tcp.connect(...)
pipe = Porc.spawn("sed 's/\(.*\)/  \1/'", in: {:socket, sock}, out: :pipe)
Porc.spawn("tr a-z A-Z", in: {:pipe, pipe}, out: :stream)
|> Stream.into(File.stream!("output.txt"))
```

In the above example two OS processes are spawned and chained together so that
the output from one process flows into standard input of the other one.

Roughly equivalent example, but this time using only streams to chain programs
together.

```elixir
# by default stream splits the content into lines; we should probably be able
# to customize that
sock = :gen_tcp.connect(...)
s1 = Porc.spawn("sed 's/\(.*\)/  \1/'", in: {:socket, sock}, out: :stream)
s2 = Porc.spawn("tr a-z A-Z", in: :stream, out: :stream)
s3 = Porc.spawn("sort", in: :stream, out: :stream)
Stream.concat([s1, s2, s3]) |> Stream.each(&IO.puts/1)
```

Note the difference: when using pipes, the chaining will be performed at the
OS level when possible. Using streams makes each program's output pass through
Elixir before going as input into another program.

### Porcelain and OTP

It is possible to spawn long-running tasks and communicate with them using
standard OTP techniques. A spawned program can also be integrated into a
supervision tree with ability to keep its state and restart in case of errors.

*to be implemeted*

---

See the tests for more usage examples.
