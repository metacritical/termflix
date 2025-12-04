#!/bin/bash

PATH=$PATH:$OH_MY_BASH/bin

BASH_LIBS=$OH_MY_BASH/libs
BASH_UTILS=$OH_MY_BASH/utils

#Global Export Scripts
source $OH_MY_BASH/bin/ansi_color
source $OH_MY_BASH/bin/term_color

#Include Clock
#source $BASH_UTILS/clock.sh

#Color Utility Functions
source $BASH_LIBS/colors.sh

#Custom Key Binder Script
source $BASH_LIBS/bind_key.sh

#Aliases
source $BASH_LIBS/aliases.sh

# Help system
omb_help() {
    if [ -f "$OH_MY_BASH/bin/omb" ]; then
        "$OH_MY_BASH/bin/omb" "$@"
    else
        echo "Help system not found. Please ensure omb is installed."
    fi
}

# Alias for help
alias omb='omb_help'
alias oh_my_bash_help='omb_help'
