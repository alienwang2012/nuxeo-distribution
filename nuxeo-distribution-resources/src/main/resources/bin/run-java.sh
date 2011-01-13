#!/bin/sh
#####
#
# Shell script calling a multi-OS Nuxeo startup script
# Will replace run.sh when Java Nuxeo Launcher will be finished 
#
#####

NUXEO_HOME=${NUXEO_HOME:-$(cd $(dirname $0)/..; pwd -P)}
PARAM_NUXEO_HOME="-Dnuxeo.home=$NUXEO_HOME/"
NUXEO_CONF=${NUXEO_CONF:-$NUXEO_HOME/bin/nuxeo.conf}
PARAM_NUXEO_CONF="-Dnuxeo.conf=$NUXEO_CONF"

## OS detection
cygwin=false
darwin=false
linux=false
case "`uname`" in
  CYGWIN*) cygwin=true;;
  Darwin*) darwin=true;;
  Linux) linux=true;;
esac

## Setup the JVM (find JAVA_HOME if undefined; use JAVA if defined)
while read line; do
  if [[ "$line" != \#* ]]; then
    $line
  fi
done <<EOF
`grep JAVA_HOME $NUXEO_CONF`
EOF
if [ -z "$JAVA" ]; then
  JAVA="java"
fi
if [ -z "$JAVA_HOME" ]; then
  JAVA=`which $JAVA`

  # follow symlinks
  while [ -h "$JAVA" ]; do
    ls=`ls -ld "$JAVA"`
    link=`expr "$ls" : '.*-> \(.*\)$'`
    if expr "$link" : '/.*' > /dev/null; then
      JAVA="$link"
    else
      JAVA=`dirname "$JAVA"`/"$link"
    fi
  done
  JAVA_HOME=`dirname "$JAVA"`
  JAVA_HOME=`dirname "$JAVA_HOME"`
fi
PATH="$JAVA_HOME/bin:$PATH"

while read line; do
  if [[ "$line" != \#* ]]; then
    JAVA_OPTS="$(echo $line|cut -d= -f2-)"
  fi
done <<EOF
`grep JAVA_OPTS $NUXEO_CONF`
EOF
[ -z "$JAVA_OPTS" ] && JAVA_OPTS="$JAVA_OPTS -Xms512m -Xmx1024m -XX:MaxPermSize=512m -Dsun.rmi.dgc.client.gcInterval=3600000 -Dsun.rmi.dgc.server.gcInterval=3600000 -Dfile.encoding=UTF-8"
# Force IPv4
JAVA_OPTS="$JAVA_OPTS -Djava.net.preferIPv4Stack=true"
# Set AWT headless
JAVA_OPTS="$JAVA_OPTS -Djava.awt.headless=true"

# If -server not set in JAVA_OPTS, set it, if supported
SERVER_SET=`echo $JAVA_OPTS | grep "\-server"`
if [ "x$SERVER_SET" = "x" ]; then
  # Check for SUN(tm) JVM w/ HotSpot support
  if [ "x$HAS_HOTSPOT" = "x" ]; then
    HAS_HOTSPOT=`"$JAVA" -version 2>&1 | grep -i HotSpot`
  fi
  # Enable -server if we have Hotspot, unless we can't
  if [ "x$HAS_HOTSPOT" != "x" ]; then
    # MacOS does not support -server flag
    if [ "$darwin" != "true" ]; then
      JAVA_OPTS="-server $JAVA_OPTS"
    fi
  fi
fi

## OS specific checks
# Check file descriptor limit is not too low
if [ "$cygwin" = "false" ]; then
  MAX_FD_LIMIT=`ulimit -H -n`
  if [ $? -eq 0 ]; then
    if [ "$darwin" = "true" ] && [ "$MAX_FD_LIMIT" = "unlimited" ]; then
      MAX_FD_LIMIT=`sysctl -n kern.maxfilesperproc`
      ulimit -n $MAX_FD_LIMIT
    fi
    if [ $MAX_FD_LIMIT -lt 2048 ]; then
      warn "Maximum file descriptor limit is too low: $MAX_FD_LIMIT"
      warn "See: $MAX_FD_LIMIT_HELP_URL"
    fi
  else
    warn "Could not get system maximum file descriptor limit (got $MAX_FD_LIMIT)"
  fi
fi

launcher() {
    NUXEO_LAUNCHER=$NUXEO_HOME/bin/nuxeo-launcher.jar
    if [ ! -e "$NUXEO_LAUNCHER" ]; then
        echo Could not locate $NUXEO_LAUNCHER. 
        # echo Please check that you are in the bin directory when running this script.
        exit 1
    fi
    echo Launcher command: $JAVA -Djava.launcher.opts="$JAVA_OPTS" "$PARAM_NUXEO_HOME" "$PARAM_NUXEO_CONF" -jar $NUXEO_LAUNCHER $@
    $JAVA -Djava.launcher.opts="$JAVA_OPTS" "$PARAM_NUXEO_HOME" "$PARAM_NUXEO_CONF" -jar $NUXEO_LAUNCHER $@
}

launcher $@