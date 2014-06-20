.PHONY: build

build: build/porcelain build/goon
	cd $< && git pull
	docker build -t porcelain $@

build/porcelain:
	git clone git@github.com:alco/porcelain.git $@

build/goon:
	wget https://github.com/alco/goon/releases/download/v1.0.1/goon_linux_amd64.tar.gz
	mv goon_linux_amd64.tar.gz build/
	cd build && tar -xf goon_linux_amd64.tar.gz
