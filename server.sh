#!/bin/sh

# echo $$ > server.pid
# echo "Server started with process :" `cat server.pid`

while `true`
do
        ./DeathL33tServer.pl >> server.log 2>&1
        if [ -f server.pid ]
        then
            return
        fi
done
