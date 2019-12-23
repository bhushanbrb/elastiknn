
pwd = $(shell pwd)
core = $(pwd)/core
vpip = ./venv/bin/pip
vpy = ./venv/bin/python
gradle = ./gradlew
eslatest = es74x
s3 = aws s3
build_bucket = s3://com-klibisz-elastiknn-builds/
dc = docker-compose
src_all = $(shell git ls-files | sed 's/\ /\\ /')

clean:
	./gradlew clean
	cd testing && $(dc) down
	rm -rf .mk/*

.mk/python3-installed:
	python3 --version > /dev/null
	python3 -m pip install -q virtualenv
	touch $@

.mk/docker-compose-installed:
	docker-compose --version > /dev/null
	touch $@

.mk/client-python-venv: .mk/python3-installed
	cd client-python && python3 -m virtualenv venv
	touch $@

.mk/client-python-install: .mk/client-python-venv
	cd client-python \
		&& $(vpip) install -q -r requirements.txt \
		&& $(vpip) install -q grpcio-tools pytest
	touch $@

.mk/gradle-gen-proto: $(src_all)
	$(gradle) generateProto
	touch $@

.mk/gradle-publish-local: $(src_all)
	$(gradle) assemble
	touch $@

.mk/client-python-compile: .mk/client-python-install .mk/gradle-gen-proto
	cd client-python \
		&& $(vpy) -m grpc_tools.protoc \
			--proto_path=$(core)/src/main/proto \
			--proto_path=$(core)/build/extracted-include-protos/main \
			--python_out=. \
			$(core)/src/main/proto/elastiknn/elastiknn.proto \
			$(core)/build/extracted-include-protos/main/scalapb/scalapb.proto \
		&& $(vpy) -c "from elastiknn.elastiknn_pb2 import Similarity; x = Similarity.values()"
	touch $@

.mk/client-python-publish-local: .mk/client-python-compile
	cd client-python && $(vpy) setup.py sdist && ls dist
	touch $@

.mk/publish-s3: .mk/gradle-publish-local .mk/client-python-publish-local
	aws s3 sync $(eslatest)/build/distributions $(build_bucket)
	aws s3 sync client-python/dist $(build_bucket)
	aws s3 ls $(build_bucket)
	touch $@

testing/cluster: .mk/python3-installed .mk/docker-compose-installed .mk/gradle-publish-local
	sudo sysctl -w vm.max_map_count=262144
	cd testing \
		&& $(dc) down \
		&& $(dc) up --detach --build --force-recreate --scale elasticsearch_data=2 \
		&& python3 cluster_ready.py