disp_msg()
{
		if [ -n "$TMUX" ]; then
				#Set Display time for status line messages i.e set-option -g display-message "hi World" would stay for 2 secs
				tmux set-option -g display-time 3000 1>/dev/null
				tmux display-message "$(fortune)"
				tmux set-option -g display-time 600 1>/dev/null
		fi
}
