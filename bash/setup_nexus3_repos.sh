#!/usr/bin/env bash

function usage() {
    echo "Main purpose of this script is to populate sample components into various NXRM3 repositories.
Also this script can be used for testing downloads and some uploads.
This script also creates repositories if it does not exist.

curl -o /var/tmp/share/sonatype/setup_nexus3_repos.sh https://raw.githubusercontent.com/hajimeo/samples/master/bash/setup_nexus3_repos.sh

Repository Naming Rules:
    <format>_(proxy|hosted|group)
    Except 'maven2', which uses 'maven'

REQUIREMENTS / DEPENDENCIES:
    If Mac, 'gsed' is required.
"
}

# Global variables
_DEFAULT_USER="${_DEFAULT_USER:-"admin"}"
_DEFAULT_PWD="${_DEFAULT_PWD:-"admin123"}"
_NEXUS_URL="${_NEXUS_URL:-"http://`hostname -f`:8081"}" #NXRM2: http://node-nxrm2.standalone.localdomain:8081/nexus/
_BLOB_NAME="${_BLOB_NAME:-"default"}"
_TMP="${_TMP:-"/tmp"}"

## for f_setup_docker()
_DOCKER_CMD="${_DOCKER_CMD-""}"
_DOCKER_PROXY="${_DOCKER_PROXY-""}"     #dh1.standalone.localdomain:18079
_DOCKER_HOSTED="${_DOCKER_HOSTED-""}"   #dh1.standalone.localdomain:18082
_DOCKER_GROUP="${_DOCKER_GROUP-""}"
_IS_NXRM2=${_IS_NXRM2:-"N"}
_NO_DATA=${_NO_DATA:-"N"}

## Misc.
_TID="${_TID:-80}"


function f_setup_maven() {
    local _prefix="${1:-"maven"}"
    # If no xxxx-proxy, create it
    if ! _does_repo_exist "${_prefix}-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"maven":{"versionPolicy":"MIXED","layoutPolicy":"PERMISSIVE"},"proxy":{"remoteUrl":"https://repo1.maven.org/maven2/","contentMaxAge":-1,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":false,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_BLOB_NAME}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"maven2-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    # If NXRM2: _get_asset_NXRM2 "${_prefix}-proxy" "junit/junit/4.12/junit-4.12.jar"
    _get_asset "${_prefix}-proxy" "junit/junit/4.12/junit-4.12.jar" "${_TMP%/}/junit-4.12.jar" || return $?

    # If no xxxx-hosted, create it
    if ! _does_repo_exist "${_prefix}-hosted"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"maven":{"versionPolicy":"MIXED","layoutPolicy":"PERMISSIVE"},"storage":{"blobStoreName":"'${_BLOB_NAME}'","strictContentTypeValidation":true,"writePolicy":"ALLOW_ONCE"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"maven2-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    #mvn deploy:deploy-file -DgroupId=junit -DartifactId=junit -Dversion=4.21 -DgeneratePom=true -Dpackaging=jar -DrepositoryId=nexus -Durl=${_NEXUS_URL}/repository/${_prefix}-hosted -Dfile=${_TMP%/}/junit-4.12.jar
    _upload_asset "${_prefix}-hosted" -F maven2.groupId=junit -F maven2.artifactId=junit -F maven2.version=4.21 -F maven2.asset1=@${_TMP%/}/junit-4.12.jar -F maven2.asset1.extension=jar

    # If no xxxx-group, create it
    if ! _does_repo_exist "${_prefix}-group"; then
        # Hosted first
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_BLOB_NAME}'","strictContentTypeValidation":true},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"maven2-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group ("." in groupdId should be changed to "/")
    _get_asset "${_prefix}-group" "org/apache/httpcomponents/httpclient/4.5.12/httpclient-4.5.12.jar" || return $?

    # Another test for get from proxy, then upload to hosted, then get from hosted
    #_get_asset "${_prefix}-proxy" "org/apache/httpcomponents/httpclient/4.5.12/httpclient-4.5.12.jar" "${_TMP%/}/httpclient-4.5.12.jar"
    #_upload_asset "${_prefix}-hosted" -F maven2.groupId=org.apache.httpcomponents -F maven2.artifactId=httpclient -F maven2.version=4.5.12 -F maven2.asset1=@${_TMP%/}/httpclient-4.5.12.jar -F maven2.asset1.extension=jar
    #_get_asset "${_prefix}-hosted" "org/apache/httpcomponents/httpclient/4.5.12/httpclient-4.5.12.jar"
}

function f_setup_pypi() {
    local _prefix="${1:-"pypi"}"
    # If no xxxx-proxy, create it
    if ! _does_repo_exist "${_prefix}-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://pypi.org","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":false,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_BLOB_NAME}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"pypi-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    _get_asset "${_prefix}-proxy" "packages/unit/0.2.2/Unit-0.2.2.tar.gz" "${_TMP%/}/Unit-0.2.2.tar.gz" || return $?

    # If no xxxx-hosted, create it
    if ! _does_repo_exist "${_prefix}-hosted"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_BLOB_NAME}'","strictContentTypeValidation":true,"writePolicy":"ALLOW_ONCE"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"pypi-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    _upload_asset "${_prefix}-hosted" -F "pypi.asset=@${_TMP%/}/Unit-0.2.2.tar.gz"

    # If no xxxx-group, create it
    if ! _does_repo_exist "${_prefix}-group"; then
        # Hosted first
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_BLOB_NAME}'","strictContentTypeValidation":true},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"pypi-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group
    _get_asset "${_prefix}-group" "packages/pyyaml/5.3.1/PyYAML-5.3.1.tar.gz" || return $?
}

function f_setup_npm() {
    local _prefix="${1:-"npm"}"
    # If no xxxx-proxy, create it
    if ! _does_repo_exist "${_prefix}-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://registry.npmjs.org","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":false,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_BLOB_NAME}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"npm-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    _get_asset "${_prefix}-proxy" "lodash/-/lodash-4.17.4.tgz" "${_TMP%/}/lodash-4.17.15.tgz" || return $?

    # If no xxxx-hosted, create it
    if ! _does_repo_exist "${_prefix}-hosted"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_BLOB_NAME}'","strictContentTypeValidation":true,"writePolicy":"ALLOW_ONCE"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"npm-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    _upload_asset "${_prefix}-hosted" -F "npm.asset=@${_TMP%/}/lodash-4.17.15.tgz"

    # If no xxxx-group, create it
    if ! _does_repo_exist "${_prefix}-group"; then
        # Hosted first
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_BLOB_NAME}'","strictContentTypeValidation":true},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"npm-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group
    _get_asset "${_prefix}-group" "grunt/-/grunt-1.1.0.tgz" || return $?
}

function f_setup_docker() {
    local _prefix="${1:-"docker"}"
    local _tag_name="${2:-"alpine:3.7"}"
    local _cmd="${3:-"${_DOCKER_CMD}"}"
    if [ -z "${_cmd}" ]; then
        which docker &>/dev/null && _cmd="docker"
        # podman is better in my opinion
        which podman &>/dev/null && _cmd="podman"
    fi

    # If no xxxx-proxy, create it
    if ! _does_repo_exist "${_prefix}-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"docker":{"forceBasicAuth":false,"v1Enabled":true},"proxy":{"remoteUrl":"https://registry-1.docker.io","contentMaxAge":1440,"metadataMaxAge":1440},"dockerProxy":{"indexType":"HUB","cacheForeignLayers":false,"useTrustStoreForIndexAccess":false},"httpclient":{"blocked":false,"autoBlock":true,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_BLOB_NAME}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"undefined":[false,false],"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"docker-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    if [ -z "${_cmd}" ]; then
        _log "WARN" "No docker or podman command, so no get test"
    elif [ -z "${_DOCKER_PROXY}" ]; then
        _log "WARN" "No _DOCKER_PROXY (hostname:port) is set, so no get test"
    else
        local _image_name="$(docker images --format "{{.Repository}}" | grep -w "${_tag_name}")"
        if [ -n "${_image_name}" ]; then
            _log "WARN" "Deleting ${_image_name} (wait for 5 secs)";sleep 5
            ${_cmd} rmi ${_image_name} || return $?
        fi
        ${_cmd} login ${_DOCKER_PROXY} --username ${_DEFAULT_USER} --password ${_DEFAULT_PWD} || return $?
        ${_cmd} pull ${_DOCKER_PROXY}/${_tag_name} || return $?
    fi

    # If no xxxx-hosted, create it
    if ! _does_repo_exist "${_prefix}-hosted"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"docker":{"forceBasicAuth":true,"v1Enabled":true},"storage":{"blobStoreName":"'${_BLOB_NAME}'","strictContentTypeValidation":true,"writePolicy":"ALLOW"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"undefined":[false,false],"recipe":"docker-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    if [ -z "${_cmd}" ]; then
        _log "WARN" "No docker or podman command, so no get test"
    elif [ -z "${_DOCKER_HOSTED}" ]; then
        # NOTE: docker hosted does not have Upload UI.
        _log "WARN" "No _DOCKER_HOSTED (hostname:port) is set, so no upload test"
    else
        ${_cmd} login ${_DOCKER_HOSTED} --username ${_DEFAULT_USER} --password ${_DEFAULT_PWD} || return $?
        # In proxy test, the image should be already pulled, so not building
        if ! ${_cmd} tag ${_DOCKER_PROXY:-"localhost"}/${_tag_name} ${_DOCKER_HOSTED}/${_tag_name}; then
            # "FROM alpine:3.7\nRUN apk add --no-cache mysql-client\nENTRYPOINT [\"mysql\"]"
            # NOTE docker build -f does not work (bug?)
            local _build_dir="$(mktemp -d)" || return $?
            cd ${_build_dir} || return $?
            echo -e "FROM ${_tag_name}\n" > Dockerfile && ${_cmd} build --rm -t ${_tag_name} .
            cd -    # should check the previous return code.
            if ! ${_cmd} tag localhost/${_tag_name} ${_DOCKER_HOSTED}/${_tag_name}; then
                ${_cmd} tag ${_tag_name} ${_DOCKER_HOSTED}/${_tag_name} || return $?
            fi
        fi
        ${_cmd} push ${_DOCKER_HOSTED}/${_tag_name} || return $?
    fi

    # If no xxxx-group, create it
    if ! _does_repo_exist "${_prefix}-group"; then
        #
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"docker":{"forceBasicAuth":true,"v1Enabled":true},"storage":{"blobStoreName":"'${_BLOB_NAME}'","strictContentTypeValidation":false},"group":{"memberNames":["docker-hosted","docker-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"undefined":[false,false],"recipe":"docker-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group
    if [ -z "${_cmd}" ]; then
        _log "WARN" "No docker or podman command, so no get test"
    elif [ -z "${_DOCKER_GROUP}" ]; then
        _log "WARN" "No _DOCKER_GROUP (hostname:port) is set, so no get test"
    else
        local _image_name="$(docker images --format "{{.Repository}}" | grep -w "hello-world")"
        if [ -n "${_image_name}" ]; then
            _log "WARN" "Deleting ${_image_name} (wait for 5 secs)";sleep 5
            ${_cmd} rmi ${_image_name} || return $?
        fi
        ${_cmd} login ${_DOCKER_GROUP} --username ${_DEFAULT_USER} --password ${_DEFAULT_PWD} || return $?
        ${_cmd} pull ${_DOCKER_GROUP}/hello-world || return $?
    fi
}

function f_setup_yum() {
    local _prefix="${1:-"yum"}"
    # If no xxxx-proxy, create it
    if ! _does_repo_exist "${_prefix}-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"http://mirror.centos.org/centos/","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":false},"storage":{"blobStoreName":"'${_BLOB_NAME}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"yum-proxy"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-proxy
    if which yum &>/dev/null; then
        _nexus_yum_repo "${_prefix}-proxy"
        yum --disablerepo="*" --enablerepo="nexusrepo" install --downloadonly --downloaddir=${_TMP%/} dos2unix || return $?
    else
        _get_asset "${_prefix}-proxy" "7/os/x86_64/Packages/dos2unix-6.0.3-7.el7.x86_64.rpm" "${_TMP%/}/dos2unix-6.0.3-7.el7.x86_64.rpm" || return $?
    fi

    # If no xxxx-hosted, create it
    if ! _does_repo_exist "${_prefix}-hosted"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"yum":{"repodataDepth":1,"deployPolicy":"PERMISSIVE"},"storage":{"blobStoreName":"'${_BLOB_NAME}'","strictContentTypeValidation":false,"writePolicy":"ALLOW"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"yum-hosted"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-hosted
    local _upload_file="$(find ${_TMP%/} -type f -size +1k -name "dos2unix-*.el7.x86_64.rpm" | tail -n1)"
    if [ -s "${_upload_file}" ]; then
        _upload_asset "${_prefix}-hosted" -F "yum.asset=@${_upload_file}" -F "yum.asset.filename=$(basename ${_upload_file})" -F "yum.directory=/7/os/x86_64/Packages" || return $?
    else
        _log "WARN" "No rpm file for upload test."
    fi
    #curl -u 'admin:admin123' --upload-file /etc/pki/rpm-gpg/RPM-GPG-KEY-pmanager ${_NEXUS_URL%/}/repository/yum-hosted/RPM-GPG-KEY-pmanager

    # If no xxxx-group, create it
    if ! _does_repo_exist "${_prefix}-group"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_BLOB_NAME}'","strictContentTypeValidation":true},"group":{"memberNames":["'${_prefix}'-hosted","'${_prefix}'-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"yum-group"}],"type":"rpc"}' || return $?
    fi
    # add some data for xxxx-group
    _get_asset "${_prefix}-group" "7/os/x86_64/Packages/$(basename ${_upload_file})" || return $?
}
function _nexus_yum_repo() {
    local _repo="${1:-"yum-group"}"
    local _out_file="${2:-"/etc/yum.repos.d/nexus-yum-test.repo"}"

    local _repo_url="${_NEXUS_URL%/}/repository/${_repo}"
echo '[nexusrepo]
name=Nexus Repository
baseurl='${_repo_url%/}'/$releasever/os/$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
priority=1' > ${_out_file}
}

function f_setup_rubygem() {
    local _prefix="${1:-"rubygem"}"
    # If no xxxx-proxy, create it
    if ! _does_repo_exist "${_prefix}-proxy"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"proxy":{"remoteUrl":"https://rubygems.org","contentMaxAge":1440,"metadataMaxAge":1440},"httpclient":{"blocked":false,"autoBlock":false,"connection":{"useTrustStore":false}},"storage":{"blobStoreName":"'${_BLOB_NAME}'","strictContentTypeValidation":true},"negativeCache":{"enabled":true,"timeToLive":1440},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-proxy","format":"","type":"","url":"","online":true,"routingRuleId":"","authEnabled":false,"httpRequestSettings":false,"recipe":"rubygems-proxy"}],"type":"rpc"}' || return $?
    fi
    # TODO: add some data for xxxx-proxy

    # If no xxxx-hosted, create it
    if ! _does_repo_exist "${_prefix}-hosted"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_BLOB_NAME}'","strictContentTypeValidation":true,"writePolicy":"ALLOW_ONCE"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"rubygems-hosted"}],"type":"rpc"}' || return $?
    fi
    # TODO: add some data for xxxx-hosted

    # If no xxxx-group, create it
    if ! _does_repo_exist "${_prefix}-group"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_BLOB_NAME}'","strictContentTypeValidation":true},"group":{"memberNames":["gems-hosted","gems-proxy"]}},"name":"'${_prefix}'-group","format":"","type":"","url":"","online":true,"recipe":"rubygems-group"}],"type":"rpc"}' || return $?
    fi
    # TODO: add some data for xxxx-group
    #_get_asset "${_prefix}-group" "7/os/x86_64/Packages/$(basename ${_upload_file})" || return $?
}


function f_setup_raw() {
    local _prefix="${1:-"raw"}"
    # TODO: If no xxxx-proxy, create it
    # TODO: add some data for xxxx-proxy

    # If no xxxx-hosted, create it
    if ! _does_repo_exist "${_prefix}-hosted"; then
        _apiS '{"action":"coreui_Repository","method":"create","data":[{"attributes":{"storage":{"blobStoreName":"'${_BLOB_NAME}'","strictContentTypeValidation":false,"writePolicy":"ALLOW"},"cleanup":{"policyName":[]}},"name":"'${_prefix}'-hosted","format":"","type":"","url":"","online":true,"recipe":"raw-hosted"}],"type":"rpc"}'
    fi
    # TODO: add some data for xxxx-hosted

    # TODO: If no xxxx-group, create it
    # TODO: add some data for xxxx-group
}

# f_get_and_upload_jars "maven" "junit" "junit" "3.8 4.0 4.1 4.2 4.3 4.4 4.5 4.6 4.7 4.8 4.9 4.10 4.11 4.12"
function f_get_and_upload_jars() {
    local _prefix="${1:-"maven"}"
    local _group_id="$2"
    local _artifact_id="$3"
    local _versions="$4"
    local _base_url="${5:-"${_NEXUS_URL}"}"

    for _v in ${_versions}; do
        # TODO: currently only maven / maven2, and doesn't work with non usual filenames
        #local _path="$(echo "${_path_with_VAR}" | sed "s/<VAR>/${_v}/g")"  # junit/junit/<VAR>/junit-<VAR>.jar
        local _path="${_group_id%/}/${_artifact_id%/}/${_v}/${_artifact_id%/}-${_v}.jar"
        local _out_path="${_TMP%/}/$(basename ${_path})"
        _log "INFO" "Downloading \"${_path}\" from \"${_prefix}-proxy\" ..."
        f_get_asset "${_prefix}-proxy" "${_path}" "${_out_path}" "${_base_url}"

        _log "INFO" "Uploading \"${_out_path}\" to \"${_prefix}-hosted\" ..."
        _upload_asset "${_prefix}-hosted" -F maven2.groupId=${_group_id%/} -F maven2.artifactId=${_artifact_id%/} -F maven2.version=${_v} -F maven2.asset1=@${_out_path} -F maven2.asset1.extension=jar
    done
}

# f_move_jars "maven-hosted" "maven-releases" "junit"
function f_move_jars() {
    local _from_repo="$1"
    local _to_repo="$2"
    local _group="$3"
    local _artifact="${4:-"*"}"
    local _version="${5:-"*"}"
    [ -z "${_group}" ] && return 11
    _api "/service/rest/v1/staging/move/${_to_repo}?repository=${_from_repo}&group=${_group}&name=${_artifact}&version=${_version}" "" "POST"
}

function f_get_asset() {
    if [[ "${_IS_NXRM2}" =~ ^[yY] ]]; then
        _get_asset_NXRM2 $@
    else
        _get_asset $@
    fi
}
function _get_asset() {
    local _repo="$1"
    local _path="$2"
    local _out_path="${3:-"/dev/null"}"
    local _base_url="${4:-"${_NEXUS_URL}"}"
    if [[ "${_NO_DATA}" =~ ^[yY] ]]; then
        _log "INFO" "_NO_DATA is set so no action."; return 0
    fi
    if [ -d "${_out_path}" ]; then
        _out_path="${_out_path%/}/$(basename ${_path})"
    fi
    curl -sf -D ${_TMP%/}/_proxy_test_header_$$.out -o ${_out_path} -u ${_DEFAULT_USER}:${_DEFAULT_PWD} -k "${_base_url%/}/repository/${_repo%/}/${_path#/}"
    local _rc=$?
    if [ ${_rc} -ne 0 ]; then
        _log "ERROR" "Failed to get ${_base_url%/}/repository/${_repo%/}/${_path#/} (${_rc})"
        cat ${_TMP%/}/_proxy_test_header_$$.out >&2
        return ${_rc}
    fi
}
# For NXRM2
function _get_asset_NXRM2() {
    local _repo="$1"
    local _path="$2"
    local _out_path="${3:-"/dev/null"}"
    local _base_url="${4:-"${_NEXUS_URL}"}"
    if [[ "${_NO_DATA}" =~ ^[yY] ]]; then
        _log "INFO" "_NO_DATA is set so no action."; return 0
    fi
    curl -sf -D ${_TMP%/}/_proxy_test_header_$$.out -o ${_out_path} -u ${_DEFAULT_USER}:${_DEFAULT_PWD} -k "${_base_url%/}/content/repository/${_repo%/}/${_path#/}"
    local _rc=$?
    if [ ${_rc} -ne 0 ]; then
        _log "ERROR" "Failed to get ${_base_url%/}/content/repository/${_repo%/}/${_path#/} (${_rc})"
        cat ${_TMP%/}/_proxy_test_header_$$.out >&2
        return ${_rc}
    fi
}
function _upload_asset() {
    local _repo="$1"
        local _forms=${@:2} #-F maven2.groupId=junit -F maven2.artifactId=junit -F maven2.version=4.21 -F maven2.asset1=@${_TMP%/}/junit-4.12.jar -F maven2.asset1.extension=jar
    local _base_url="${_NEXUS_URL}"
    if [[ "${_NO_DATA}" =~ ^[yY] ]]; then
        _log "INFO" "_NO_DATA is set so no action."; return 0
    fi
    curl -sf -D ${_TMP%/}/_upload_test_header_$$.out -u ${_DEFAULT_USER}:${_DEFAULT_PWD} -H "accept: application/json" -H "Content-Type: multipart/form-data" -X POST -k "${_base_url%/}/service/rest/v1/components?repository=${_repo}" ${_forms}
    local _rc=$?
    if [ ${_rc} -ne 0 ]; then
        if grep -qE '^HTTP/1.1 [45]' ${_TMP%/}/_upload_test_header_$$.out; then
            _log "ERROR" "Failed to post to ${_base_url%/}/service/rest/v1/components?repository=${_repo} (${_rc})"
            cat ${_TMP%/}/_upload_test_header_$$.out >&2
            return ${_rc}
        else
            _log "WARN" "Post to ${_base_url%/}/service/rest/v1/components?repository=${_repo} might have been failed (${_rc})"
            cat ${_TMP%/}/_upload_test_header_$$.out >&2
        fi
    fi
}
function _does_repo_exist() {
    local _repo_name="$1"
    # At this moment, not always checking
    find ${_TMP%/}/ -type f -name '_does_repo_exist*.out' -mmin +5 -delete
    if [ ! -s ${_TMP%/}/_does_repo_exist$$.out ]; then
        _api "/service/rest/v1/repositories" | grep '"name":' > ${_TMP%/}/_does_repo_exist$$.out
    fi
    if [ -n "${_repo_name}" ]; then
        # case insensitive
        grep -iq "\"${_repo_name}\"" ${_TMP%/}/_does_repo_exist$$.out
    fi
}
function _does_blob_exist() {
    local _blob_name="$1"
    # At this moment, not always checking
    find ${_TMP%/}/ -type f -name '_does_blob_exist*.out' -mmin +5 -delete
    if [ ! -s ${_TMP%/}/_does_blob_exist$$.out ]; then
        _api "/service/rest/beta/blobstores" | grep '"name":' > ${_TMP%/}/_does_blob_exist$$.out
    fi
    if [ -n "${_blob_name}" ]; then
        # case insensitive
        grep -iq "\"${_blob_name}\"" ${_TMP%/}/_does_blob_exist$$.out
    fi
}
function _apiS() {
    local __doc__="NXRM (not really API but) API wrapper with session"
    local _data="${1}"
    local _method="${2}"
    local _usr="${3:-${_DEFAULT_USER}}"
    local _pwd="${4-${_DEFAULT_PWD}}"   # Accept an empty password
    local _nexus_url="${5:-${_NEXUS_URL}}"

    local _usr_b64="$(_b64_url_enc "${_usr}")"
    local _pwd_b64="$(_b64_url_enc "${_pwd}")"
    local _user_pwd="username=${_usr_b64}&password=${_pwd_b64}"
    [ -n "${_data}" ] && [ -z "${_method}" ] && _method="POST"
    [ -z "${_method}" ] && _method="GET"

    # Mac's /tmp is symlink so without the ending "/", would needs -L but does not work with -delete
    find ${_TMP%/}/ -type f -name '.nxrm_c_*' -mmin +10 -delete
    local _c="${_TMP%/}/.nxrm_c_$$"
    if [ ! -s ${_c} ]; then
        curl -sf -D ${_TMP%/}/_apiS_header_$$.out -b ${_c} -c ${_c} -o/dev/null -k "${_nexus_url%/}/service/rapture/session" -d "${_user_pwd}"
        local _rc=$?
        if [ "${_rc}" != "0" ] ; then
            rm -f ${_c}
            return ${_rc}
        fi
    fi
    # TODO: not sure if this is needed. seems cookie works with 3.19.1 but not sure about older version
    local _H="NXSESSIONID: $(_sed -nr 's/.+\sNXSESSIONID\s+([0-9a-f]+)/\1/p' ${_c})"
    local _content_type="Content-Type: application/json"
    if [ "${_data:0:1}" != "{" ]; then
        _content_type="Content-Type: text/plain"
    elif [[ ! "${_data}" =~ "tid" ]]; then
        _data="${_data%\}},\"tid\":${_TID}}"
        _TID=$(( ${_TID} + 1 ))
    fi

    if [ -z "${_data}" ]; then
        # GET and DELETE *can not* use Content-Type json
        curl -sf -D ${_TMP%/}/_apiS_header_$$.out -b ${_c} -c ${_c} -k "${_nexus_url%/}/service/extdirect" -X ${_method} -H "${_H}"
    else
        curl -sf -D ${_TMP%/}/_apiS_header_$$.out -b ${_c} -c ${_c} -k "${_nexus_url%/}/service/extdirect" -X ${_method} -H "${_H}" -H "${_content_type}" -d ${_data}
    fi > ${_TMP%/}/_apiS_nxrm$$.out
    local _rc=$?
    if [ ${_rc} -ne 0 ]; then
        cat ${_TMP%/}/_apiS_header_$$.out >&2
        return ${_rc}
    fi
    if ! cat ${_TMP%/}/_apiS_nxrm$$.out | python -m json.tool 2>/dev/null; then
        cat ${_TMP%/}/_apiS_nxrm$$.out
    fi
}
function _api() {
    local __doc__="NXRM3 API wrapper"
    local _path="${1}"
    local _data="${2}"
    local _method="${3}"
    local _usr="${4:-${_DEFAULT_USER}}"
    local _pwd="${5-${_DEFAULT_PWD}}"   # If explicitly empty string, curl command will ask password (= may hang)
    local _nexus_url="${6:-${_NEXUS_URL}}"

    local _user_pwd="${_usr}"
    [ -n "${_pwd}" ] && _user_pwd="${_usr}:${_pwd}"
    [ -n "${_data}" ] && [ -z "${_method}" ] && _method="POST"
    [ -z "${_method}" ] && _method="GET"
    # TODO: check if GET and DELETE *can not* use Content-Type json?
    local _content_type="Content-Type: application/json"
    [ "${_data:0:1}" != "{" ] && _content_type="Content-Type: text/plain"

    if [ -z "${_data}" ]; then
        # GET and DELETE *can not* use Content-Type json
        curl -sf -D ${_TMP%/}/_api_header_$$.out -u "${_user_pwd}" -k "${_nexus_url%/}/${_path#/}" -X ${_method}
    else
        curl -sf -D ${_TMP%/}/_api_header_$$.out -u "${_user_pwd}" -k "${_nexus_url%/}/${_path#/}" -X ${_method} -H "${_content_type}" -d "${_data}"
    fi > ${_TMP%/}/f_api_nxrm_$$.out
    local _rc=$?
    if [ ${_rc} -ne 0 ]; then
        cat ${_TMP%/}/_api_header_$$.out >&2
        return ${_rc}
    fi
    if ! cat ${_TMP%/}/f_api_nxrm_$$.out | python -m json.tool 2>/dev/null; then
        echo -n `cat ${_TMP%/}/f_api_nxrm_$$.out`
        echo ""
    fi
}

function _b64_url_enc() {
    python -c "import base64, urllib; print(urllib.quote(base64.urlsafe_b64encode('$1')))"
    #python3 -c "import base64, urllib.parse; print(urllib.parse.quote(base64.urlsafe_b64encode('$1'.encode('utf-8')), safe=''))"
}
function _sed() {
    # To support Mac...
    local _cmd="sed"; which gsed &>/dev/null && _cmd="gsed"
    ${_cmd} "$@"
}
function _log() {
    # At this moment, outputting to STDERR
    if [ -n "${_LOG_FILE_PATH}" ]; then
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%Sz')] $@" | tee -a ${_LOG_FILE_PATH} 1>&2
    else
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%Sz')] $@" 1>&2
    fi
}



main() {
    if ! _does_blob_exist "${_BLOB_NAME}"; then
        if [ -s ${_TMP%/}/_does_blob_exist$$.out ]; then
            _log "ERROR" "Blobstore ${_BLOB_NAME} does not exist."
            return 1
        else
            _log "WARN" "Blobstore ${_BLOB_NAME} *may* not exist, but keep continuing..."
            sleep 5
        fi
    fi
    f_setup_maven
    f_setup_pypi
    f_setup_npm
    f_setup_docker
    f_setup_yum
    f_setup_rubygem
    f_setup_raw
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main
fi