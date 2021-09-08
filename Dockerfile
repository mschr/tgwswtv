FROM docker.elastic.co/logstash/logstash:7.9.3

COPY ./etc/logstash/ /etc/logstash/
USER root
RUN curl -s L https://dev.mysql.com/downloads/file/?id=498586 \
> $(dirname $(dirname $(readlink -f $(which java))))/mysql-connector-java-8.0.22.tar.gz

USER 1000
