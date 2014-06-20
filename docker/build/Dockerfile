FROM alco/ubuntu-elixir:v0.13.3
MAINTAINER Alexei Sholik <alcosholik@gmail.com>

ADD porcelain /home/porcelain
ADD goon /home/porcelain/goon

WORKDIR /home/porcelain
RUN MIX_ENV=test mix compile

CMD mix test --no-compile --trace
