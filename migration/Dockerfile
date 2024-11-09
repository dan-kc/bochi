FROM flyway/flyway

COPY ./sql /flyway/sql
COPY ./flyway.toml /flyway/conf
# # # ENTRYPOINT ["tail", "-f", "/dev/null"]
CMD ["migrate"]
