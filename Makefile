.PHONY: build all run-test run-non-root-test rm-test

all: build 

build:
	docker build ./ -f ./Dockerfile -t kozmo-builder:local

run-test:
	docker run -d -p 80:2022 --name kozmo_builder_local -v ~/kozmo-database:/opt/kozmo/database -v ~/kozmo-drive:/opt/kozmo/drive kozmo-builder:local

run-non-root-test:
	docker run -d -p 80:2022 --name kozmo_builder_local --user 1002:1002 -v ~/kozmo-database:/opt/kozmo/database -v ~/kozmo-drive:/opt/kozmo/drive kozmo-builder:local

rm-test:
	docker stop kozmo_builder_local; docker rm kozmo_builder_local;

 	
