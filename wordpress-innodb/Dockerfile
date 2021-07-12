FROM oraclelinux:8.4

RUN dnf install -y wget python3 && wget https://dev.mysql.com/get/Downloads/MySQL-Shell/mysql-shell-8.0.25-1.el8.x86_64.rpm && rpm -ivh mysql-shell-8.0.25-1.el8.x86_64.rpm && rm -rf mysql-shell-8.0.25-1.el8.x86_64.rpm

ENTRYPOINT ["/usr/bin/mysqlsh"]