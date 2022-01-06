#!/bin/bash
# Created by K8sCat <k8scat@gmail.com>
set +e

function init() {
  for f in /mirror-git/functions/*; do
    # shellcheck disable=SC1090
    source "${f}"
  done

  WORKDIR="/data/repos"
  mkdir -p ${WORKDIR}
  cd ${WORKDIR} || exit 1

  export INPUT_SOURCE_TOKEN_USERNAME="${INPUT_SOURCE_TOKEN_USERNAME:-${INPUT_SOURCE_USERNAME}}"
  export INPUT_SOURCE_PROTOCOL="${INPUT_SOURCE_PROTOCOL:-https}"
  export INPUT_SOURCE_HOST="${INPUT_SOURCE_HOST:-github.com}"
  export INPUT_DEST_TOKEN_USERNAME="${INPUT_DEST_TOKEN_USERNAME:-${INPUT_DEST_USERNAME}}"
  export INPUT_DEST_PROTOCOL="${INPUT_DEST_PROTOCOL:-https}"
  export INPUT_DEST_HOST="${INPUT_DEST_HOST:-github.com}"
  export INPUT_PUSH_TAGS="${INPUT_PUSH_TAGS:-true}"
  export INPUT_FORCE_PUSH="${INPUT_FORCE_PUSH:-false}"
  export INPUT_NOTIFY_PREFIX="${INPUT_NOTIFY_PREFIX:-Mirror Git}"
  export INPUT_NOTIFY_SUFFIX="${INPUT_NOTIFY_SUFFIX:-Powered by https://github.com/k8scat/action-mirror-git}"
  export INPUT_ENABLE_GIT_LFS="${INPUT_ENABLE_GIT_LFS:-false}"
}

function init_token_username() {
  if [[ -z "${INPUT_SOURCE_TOKEN_USERNAME}" ]]; then
    export INPUT_SOURCE_TOKEN_USERNAME="${INPUT_SOURCE_USERNAME}"
  fi
  if [[ -z "${INPUT_DEST_TOKEN_USERNAME}" ]]; then
    export INPUT_DEST_TOKEN_USERNAME="${INPUT_DEST_USERNAME}"
  fi
}

function init_scripts() {
  # create_repo
  if [[ -n "${INPUT_DEST_CREATE_REPO_SCRIPT}" ]]; then
    if [[ $(echo "${INPUT_DEST_CREATE_REPO_SCRIPT}" | wc -l) -eq 1 && "${INPUT_DEST_CREATE_REPO_SCRIPT}" =~ "http".*"://".* ]]; then
      if ! curl -L "${INPUT_DEST_CREATE_REPO_SCRIPT}" -o /usr/bin/create_repo; then
        exit 1
      fi
    else
      echo "${INPUT_DEST_CREATE_REPO_SCRIPT}" > /usr/bin/create_repo
    fi
    chmod +x /usr/bin/create_repo
  fi

  # delete_repo
  if [[ -n "${INPUT_DEST_DELETE_REPO_SCRIPT}" ]]; then
    if [[ $(echo "${INPUT_DEST_DELETE_REPO_SCRIPT}" | wc -l) -eq 1 && "${INPUT_DEST_CREATE_REPO_SCRIPT}" =~ "http".*"://".* ]]; then
      if ! curl -L -k "${INPUT_DEST_CREATE_REPO_SCRIPT}" -o /usr/bin/delete_repo; then
        exit 1
      fi
    else
      echo "${INPUT_DEST_CREATE_REPO_SCRIPT}" > /usr/bin/delete_repo
    fi
    chmod +x /usr/bin/delete_repo
  fi
}

# message
function init_message() {
  if [[ -n "${INPUT_SLACK_WEBHOOK}" ]]; then
    export SLACK_WEBHOOK="${INPUT_SLACK_WEBHOOK}"
  fi
  if [[ -n "${INPUT_DINGTALK_WEBHOOK}" ]]; then
    export DINGTALK_WEBHOOK="${INPUT_DINGTALK_WEBHOOK}"
  fi
  if [[ -n "${INPUT_LARK_WEBHOOK}" ]]; then
    export LARK_WEBHOOK="${INPUT_LARK_WEBHOOK}"
  fi
}

function notify() {
  local msg="${1}"
  echo "notify: ${msg}"

  if [[ -n "${INPUT_NOTIFY_PREFIX}" ]]; then
    msg="[${INPUT_NOTIFY_PREFIX}] ${msg}"
  fi
  if [[ -n "${GITHUB_SERVER_URL}" && -n "${GITHUB_REPOSITORY}" && -n "${GITHUB_RUN_ID}" ]]; then
    local run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
    msg="${msg}\n\nrun_url: ${run_url}"
  fi
  if [[ -n "${INPUT_NOTIFY_SUFFIX}" ]]; then
    msg="${msg}\n\n${INPUT_NOTIFY_SUFFIX}"
  fi

  if [[ -n "${SLACK_WEBHOOK}" ]]; then
    slack_notify "${msg}"
  fi
  if [[ -n "${DINGTALK_WEBHOOK}" ]]; then
    dingtalk_notify "${msg}"
  fi
  if [[ -n "${LARK_WEBHOOK}" ]]; then
    lark_notify "${msg}"
  fi
  return 0
}

function write_ssh_config() {
  type=$1
  host=$2
  port=$3
  username=$4
  private_key=$5

  local privkey_file="${SSH_DIR}/id_rsa_${username}"
  echo "${private_key}" > "${privkey_file}"
  chmod 0600 "${privkey_file}"

  new_host="${type}.${username}.${host}"
  cat >> "${SSH_DIR}/config" <<EOF
Host ${new_host}
    HostName ${host}
    User git
    Port ${port:-22}
    IdentityFile ${privkey_file}
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
  echo "${new_host}"
}

function init_ssh() {
  SSH_DIR="${HOME}/.ssh"
  mkdir -p "${SSH_DIR}"
  chmod 0700 "${SSH_DIR}"

  if [[ "${INPUT_SOURCE_PROTOCOL}" = "ssh" ]]; then
    INPUT_SOURCE_HOST=$(write_ssh_config "source" "${INPUT_SOURCE_HOST}" "${INPUT_SOURCE_PORT}" "${INPUT_SOURCE_USERNAME}" "${INPUT_SOURCE_PRIVATE_KEY}")
    export INPUT_SOURCE_HOST
  fi
  if [[ "${INPUT_DEST_PROTOCOL}" = "ssh" ]]; then
    INPUT_DEST_HOST=$(write_ssh_config "dest" "${INPUT_DEST_HOST}" "${INPUT_DEST_PORT}" "${INPUT_DEST_USERNAME}" "${INPUT_DEST_PRIVATE_KEY}")
    export INPUT_DEST_HOST
  fi
}

function gen_source_addr() {
  if [[ "${INPUT_SOURCE_PROTOCOL}" = "ssh" ]]; then
    source_addr="git@${INPUT_SOURCE_HOST}:${INPUT_SOURCE_USERNAME}/${REPO_NAME}.git"
    echo "${source_addr}"
    return
  fi
  if [[ "${INPUT_SOURCE_PROTOCOL}" = "https" ]]; then
    source_addr="https://${INPUT_SOURCE_TOKEN_USERNAME}:${INPUT_SOURCE_TOKEN}@${INPUT_SOURCE_HOST}"
    if [[ -n "${INPUT_SOURCE_PORT}" ]]; then
      source_addr="${source_addr}:${INPUT_SOURCE_PORT}"
    fi
    source_addr="${source_addr}/${INPUT_SOURCE_USERNAME}/${REPO_NAME}.git"
    echo "${source_addr}"
    return
  fi
  notify "Unknown source protocol: ${INPUT_SOURCE_PROTOCOL}"
  return 0
}

function gen_dest_addr() {
  if [[ "${INPUT_DEST_PROTOCOL}" = "ssh" ]]; then
    dest_addr="git@${INPUT_DEST_HOST}:${INPUT_DEST_USERNAME}/${REPO_NAME}.git"
    echo "${dest_addr}"
    return
  fi
  if [[ "${INPUT_DEST_PROTOCOL}" = "https" ]]; then
    dest_addr="https://${INPUT_DEST_TOKEN_USERNAME}:${INPUT_DEST_TOKEN}@${INPUT_DEST_HOST}"
    if [[ -n "${INPUT_DEST_PORT}" ]]; then
      dest_addr="${dest_addr}:${INPUT_DEST_PORT}"
    fi
    dest_addr="${dest_addr}/${INPUT_DEST_USERNAME}/${REPO_NAME}.git"
    echo "${dest_addr}"
    return
  fi
  notify "Unknown dest protocol: ${INPUT_DEST_PROTOCOL}"
  return 0
}

function mirror() {
  IFS=","
  for repo_name in ${INPUT_MIRROR_REPOS}; do
    # shellcheck disable=SC2076
    if [[ "${INPUT_IGNORED_REPOS}" =~ "${repo_name}" ]]; then
      continue
    fi
    export REPO_NAME="${repo_name}"

    cd ${WORKDIR} || return 1

    source_addr=$(gen_source_addr)
    echo "source_addr: ${source_addr}"

    dest_addr=$(gen_dest_addr)
    echo "dest_addr: ${dest_addr}"

    if ! git clone --bare "${source_addr}" "${REPO_NAME}"; then
      notify "Failed to clone ${source_addr}"
      return 1
    fi

    if [[ -n "${INPUT_DEST_CREATE_REPO_SCRIPT}" ]]; then
      echo "Creating repo: ${REPO_NAME}"
      set -x
      if ! create_repo; then
        notify "Failed to create repo: ${REPO_NAME}"
        return 1
      fi
      set +x
    fi

    repo_dir="${WORKDIR}/${REPO_NAME}"
    cd "${repo_dir}" || exit 1
    # shellcheck disable=SC2076
    if [[ "${INPUT_PUSH_TAGS}" = "false" || "${INPUT_SKIP_TAGS_REPOS}" =~ "${REPO_NAME}" ]]; then
      if ! git push --all -f "${dest_addr}"; then
        notify "Failed to push ${REPO_NAME} to ${dest_addr} with --all flag"
        if [[ "${INPUT_FORCE_PUSH}" = "true" && -n "${INPUT_DEST_DELETE_REPO_SCRIPT}" && -n "${INPUT_DEST_CREATE_REPO_SCRIPT}" ]]; then
          echo "Deleting repo: ${REPO_NAME}"
          set -x
          if ! delete_repo; then
            notify "Failed to delete repo: ${REPO_NAME}"
            return 1
          fi
          set +x

          echo "Creating repo: ${REPO_NAME}"
          set -x
          if ! create_repo; then
            notify "Failed to create repo: ${REPO_NAME}"
            return 1
          fi
          set +x

          if ! git push --all -f "${dest_addr}"; then
            notify "Still failed to push ${REPO_NAME} to ${dest_addr} with --all flag"
            return 1
          fi
        fi
      fi
    else
      if ! git push --mirror -f "${dest_addr}"; then
        notify "Failed to push ${REPO_NAME} to ${dest_addr} with --mirror flag"
        if [[ "${INPUT_FORCE_PUSH}" = "true" && -n "${INPUT_DEST_DELETE_REPO_SCRIPT}" && -n "${INPUT_DEST_CREATE_REPO_SCRIPT}" ]]; then
          echo "Deleting repo: ${REPO_NAME}"
          set -x
          if ! delete_repo; then
            notify "Failed to delete repo: ${REPO_NAME}"
            return 1
          fi
          set +x

          echo "Creating repo: ${REPO_NAME}"
          set -x
          if ! create_repo; then
            notify "Failed to create repo: ${REPO_NAME}"
            return 1
          fi
          set +x

          if ! git push --mirror -f "${dest_addr}"; then
            notify "Still failed to push ${REPO_NAME} to ${dest_addr} with --mirror flag"
            return 1
          fi
        fi
      fi
    fi

    if [[ "${INPUT_ENABLE_GIT_LFS}" = "true" ]]; then
      cd "${REPO_NAME}" || return 1
      git lfs fetch --all
      git lfs push --all "${dest_addr}"
    fi
  done
}

function main() {
  init
  init_token_username
  init_scripts
  init_message
  init_ssh

  notify "Mirror Git starting"
  if mirror; then
    notify "Mirror Git finished"
  else
    notify "Mirror Git failed"
    return 1
  fi
}

main "$@"
