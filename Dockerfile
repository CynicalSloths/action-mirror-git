FROM ghcr.io/gigrator/base:0.0.8
LABEL maintainer="CynicalSloths <cynicalsloths@gmail.com>"
LABEL repository="https://github.com/CynicalSloths/action-mirror-git.git"
COPY mirror.sh /mirror.sh
ENTRYPOINT ["/mirror.sh"]
