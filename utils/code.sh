#!/bin/bash

code()
{
		local rvm_current=$(rvm current)
		local file=$(echo ${@: - 1}) #Last Argument must be a file.9
		rvm use system 1>/dev/null
		coderay ${file}
		rvm use ${rvm_current} 1>/dev/null
		return 0
}
