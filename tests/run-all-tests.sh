#!/bin/bash

# Start the ceph/demo docker container.
function start_docker() {
    local DOCKER0_SUBNET=`ip -o -f inet addr show | awk '/scope global docker0/ {print $4}'`

    echo "Building container..."

    local DOCKER_CONTAINER=`docker build ceph-test-docker | awk '/Successfully built/ { print $3 }'`

	echo "Built container: ${DOCKER_CONTAINER}"

    # We store the running docker container's ID into the temporary file `.tmp_tc_name`
    # so that we can remember it through subshells and in case something goes wrong
    # and the docker container isn't stopped (i.e. Ctrl-C during running tests.)
    local DOCKER_CMD=""
    DOCKER_CMD+="docker run -d --rm --net=host -v $(pwd)/ceph:/etc/ceph "
    DOCKER_CMD+="-e CEPH_PUBLIC_NETWORK=${DOCKER0_SUBNET} "
    DOCKER_CMD+="-e MON_IP=127.0.0.1 "
    DOCKER_CMD+="--entrypoint=/preentry.sh ${DOCKER_CONTAINER}"

	echo "Starting Ceph demo container with '${DOCKER_CMD}'..."

    $DOCKER_CMD > .tmp_tc_name
    
    echo "Started Ceph demo container: $(cat .tmp_tc_name)"
    echo "Waiting for Ceph demo container to be ready for tests..."

    ./do_until_success.sh "docker logs $(cat .tmp_tc_name) | grep -q '/entrypoint.sh: SUCCESS'" 2> /dev/null

    echo "Attempting to fix permissions on ceph/ceph/client.admin.keyring from inside the container..."

    # The devil's permissions for a total hack
    docker exec $(cat .tmp_tc_name) chmod 666 /etc/ceph/ceph.client.admin.keyring
    
    echo "Done."
}

# Stop the last running ceph/demo docker container.
function stop_docker() {
    if [[ -e .tmp_tc_name ]]; then
	echo "Stopping docker container: $(docker kill $(cat .tmp_tc_name))"
    fi
}

# Fill test files with random ASCII.
function make_test_files() {
    for TEST_FILE in $@ 
    do
	base64 /dev/urandom | head -c 1M > $TEST_FILE
    done

    echo "$@" > .tmp_test_files
}

function cleanup_test_files() {
    rm -f `cat .tmp_test_files` .tmp_test_files
}

# During setup, we kill the previous docker container if it's still running. Then,
# start a new one.
function setup() {
    (
        cd "$(dirname $0)"
	
	TEST_FILES=""

	for N in {0..4}
	do
	    TEST_FILES+="integration/read_write_remove/test_file$N "
	done

	TEST_FILES+="integration/reader_writer/test_file.txt"

	make_test_files $TEST_FILES


        if [[ -e .tmp_tc_name && ! -z $(cat .tmp_tc_name) ]]; then
            echo "Previous docker container appears to still be running: $(cat .tmp_tc_name)"
            stop_docker
        fi

        start_docker
    )
}

# During teardown, we kill the running docker container and get rid of the temporary
# file recording the ID of the running docker container.
function teardown() {
    (
        cd "$(dirname $0)"
        stop_docker

        rm -f .tmp_tc_name

	cleanup_test_files
    )
}


export RUST_TEST_THREADS=1

setup || {
    teardown
    exit 1
}

cargo test --features integration-tests $@ || {
    teardown
    exit 1
}

teardown
