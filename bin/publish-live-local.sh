#!/bin/bash

# Include the user-specific profile
. $HOME/.bash_profile

cd ..
exec grunt publish:dev 2>&1 |tee logs/publish.log
