#!/bin/sh

PID="`cat server.pid`"
rm server.pid

echo "Killing Server at pid : $PID"
echo kill -9 $PID
kill -9 $PID
