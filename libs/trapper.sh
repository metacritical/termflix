trapper() { 
		local -A TRAP=([ERR_CODE]=$? [LAST_COMMAND]=$BASH_COMMAND)

		if [[ ${TRAP[ERR_CODE]} -ge 0 ]]; then
				echo -e '\e[1;31m'Command executed is ${TRAP[LAST_COMMAND]}'\e[0m'
				echo -e '\e[1;31m'Error code ${TRAP[ERR_CODE]}'\e[0m'
				#unset TRAP
				#set $?="1"
				#$(exit 0)
		fi 
		return 0
}

#Bash Trapper
trap 'trapper $BASH_COMMAND' ERR #> /dev/null 2>&1
