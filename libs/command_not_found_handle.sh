command_not_found_handle() { 
		local -A TRAP=([ERR_CODE]=$? [LAST_COMMAND]=$1)
		
		if [[ ${TRAP[ERR_CODE]} -ge 0 ]]; then
				echo -e '\e[1;31m'Command executed is ${TRAP[LAST_COMMAND]}'\e[0m'
				echo -e '\e[1;31m'Error code ${TRAP[ERR_CODE]}'\e[0m'
		fi 
		return 0
}

#Bash Trapper
trap 'command_not_found_handle $BASH_COMMAND' ERR #> /dev/null 2>&1
