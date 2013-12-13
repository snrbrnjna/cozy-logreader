#!/bin/bash

cd $HOME/webapps/notwist
exec /home/notwist/bin/grunt publish:live 2>&1 |tai64n |tee logs/publish.log
