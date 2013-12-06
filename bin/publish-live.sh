#!/bin/bash

cd $HOME/webapps/notwist
exec /home/notwist/bin/grunt publish:live 2>&1 |tee logs/grunt.publish.live.log