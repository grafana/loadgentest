FROM jstarcher/siege

#
# Note that this Siege has no HTTPS functionality
#

# Siege refuses to change log path when using -l flag, and insists on
# creating a logfile in /usr/local/var/log, of all places...
RUN mkdir -p /usr/local/var/log

ENTRYPOINT ["/usr/bin/siege"]
CMD ["--help"]
